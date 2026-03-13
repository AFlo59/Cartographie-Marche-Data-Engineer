# Guide pas à pas — Secret Manager runtime (INFRA-06)

Ce guide traite uniquement la partie Secret Manager runtime : création des conteneurs, ajout des versions réelles, bindings IAM et vérifications.

Prérequis déjà documentés ailleurs :
- setup manuel GCP : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- exécution Docker et authentification locale : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- matrice complète des rôles : [docs/infra/iam_roles.md](../infra/iam_roles.md)

> Ce guide sert à préparer les secrets runtime pour le développement et pour la plateforme.
> Le déploiement principal de l'infrastructure reste piloté par GitHub Actions.

---

## 0) Prérequis

- Le projet GCP est déjà préparé.
- L'authentification `gcloud` fonctionne déjà dans le contexte utilisé.
- Les rôles IAM nécessaires sont déjà attribués.

Ce guide part du principe que vous avez déjà suivi les guides précédents.

---

## 1) Vérifier le contexte et l'API

```bash
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac gcloud config get-value project
docker compose run --rm infra-iac gcloud services list --enabled --filter="name:secretmanager.googleapis.com"
```

Résultat attendu : projet actif `cartographie-data-engineer` et API Secret Manager activée.

Si l'API n'est pas activée :

```bash
docker compose run --rm infra-iac gcloud services enable secretmanager.googleapis.com --project cartographie-data-engineer
```

---

## 2) Vérifier les permissions IAM (cause la plus fréquente)

Pour créer des secrets, il faut au minimum un rôle contenant :
- `secretmanager.secrets.create`
- `secretmanager.versions.add`

Rôles pratiques :
- `roles/secretmanager.admin` (admin complet)
- ou combinaison custom plus restrictive.

Diagnostic rapide :

```bash
docker compose run --rm infra-iac gcloud projects get-iam-policy cartographie-data-engineer --flatten="bindings[].members" --filter="bindings.members:user:YOUR_USER_EMAIL" --format="table(bindings.role)"
```

Si vous n’avez pas les rôles requis, demandez à un admin projet d’exécuter :

```bash
docker compose run --rm infra-iac gcloud projects add-iam-policy-binding cartographie-data-engineer --member="user:YOUR_USER_EMAIL" --role="roles/secretmanager.admin"
```

Note PowerShell : utilisez la commande sur **une seule ligne** (pas de `\` de continuation shell).

Placeholders utilisés dans cette section :
- `YOUR_USER_EMAIL` = email de l'utilisateur humain auquel on veut donner un rôle projet.

Note : si la commande de diagnostic affiche déjà `roles/owner` ou `roles/secretmanager.admin`, vous avez déjà les droits nécessaires et vous pouvez passer à l’étape 3.

---

## 3) Créer les secrets (sans exposer les valeurs dans l’historique shell)

Secrets backlog INFRA-06 :
- `FT_CLIENT_ID`
- `FT_CLIENT_SECRET`

Secrets projet recommandés (scope actuel infra/ingestion) :
- `FT_CLIENT_ID` (obligatoire)
- `FT_CLIENT_SECRET` (obligatoire)
- `DATAGOUV_API_KEY` (optionnel, seulement si activation d'auth côté data.gouv.fr)

Note importante (bucket raw INFRA-02) : l’accès au bucket se fait par IAM/service account, **pas** par secret `bucket_id/secret`.
Le compte `ingestion-sa` doit avoir les rôles GCS nécessaires (INFRA-07).

### 3.1 Créer les conteneurs de secrets

Si vous avez déjà exécuté `terraform apply` avec le module secrets, cette étape peut déjà être faite. Sinon, créez les conteneurs manuellement.

```bash
docker compose run --rm infra-iac gcloud secrets create FT_CLIENT_ID --replication-policy="automatic" --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets create FT_CLIENT_SECRET --replication-policy="automatic" --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets create DATAGOUV_API_KEY --replication-policy="automatic" --project cartographie-data-engineer
```

Si un secret existe déjà, ignorer l’erreur `ALREADY_EXISTS`.

### 3.2 Ajouter une version (valeur)

Option sûre (interactif, sans mettre la valeur en clair dans la commande) :

```bash
docker compose run --rm -it infra-iac bash -lc 'read -rsp "FT_CLIENT_ID: " FTID; echo; printf "%s" "$FTID" | gcloud secrets versions add FT_CLIENT_ID --data-file=- --project cartographie-data-engineer'

docker compose run --rm -it infra-iac bash -lc 'read -rsp "FT_CLIENT_SECRET: " FTSEC; echo; printf "%s" "$FTSEC" | gcloud secrets versions add FT_CLIENT_SECRET --data-file=- --project cartographie-data-engineer'

docker compose run --rm -it infra-iac bash -lc 'read -rsp "DATAGOUV_API_KEY (optionnel): " DGKEY; echo; printf "%s" "$DGKEY" | gcloud secrets versions add DATAGOUV_API_KEY --data-file=- --project cartographie-data-engineer'
```

Pourquoi : `sh` (dash) ne supporte pas `read -s`, d'où l'erreur `Illegal option -s`. Utiliser `bash` corrige ce point.

Alternative non interactive (fichier local temporaire, puis suppression) :

```bash
docker compose run --rm infra-iac sh -lc 'printf "%s" "VOTRE_FT_CLIENT_ID" > /tmp/ft_client_id.txt; gcloud secrets versions add FT_CLIENT_ID --data-file=/tmp/ft_client_id.txt --project cartographie-data-engineer; rm -f /tmp/ft_client_id.txt'
docker compose run --rm infra-iac sh -lc 'printf "%s" "VOTRE_FT_CLIENT_SECRET" > /tmp/ft_client_secret.txt; gcloud secrets versions add FT_CLIENT_SECRET --data-file=/tmp/ft_client_secret.txt --project cartographie-data-engineer; rm -f /tmp/ft_client_secret.txt'
docker compose run --rm infra-iac sh -lc 'printf "%s" "VOTRE_DATAGOUV_API_KEY" > /tmp/datagouv_api_key.txt; gcloud secrets versions add DATAGOUV_API_KEY --data-file=/tmp/datagouv_api_key.txt --project cartographie-data-engineer; rm -f /tmp/datagouv_api_key.txt'
```

Placeholders utilisés dans cette section :
- `VOTRE_FT_CLIENT_ID` = identifiant OAuth2 de l'application France Travail.
- `VOTRE_FT_CLIENT_SECRET` = secret OAuth2 de l'application France Travail.
- `VOTRE_DATAGOUV_API_KEY` = clé API Data Gouv si vous utilisez cette source avec authentification.

---

## 4) Donner l’accès aux Service Accounts applicatifs

D’après votre `.env` actuel, principaux comptes :
- `ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com`
- `dbt-sa@cartographie-data-engineer.iam.gserviceaccount.com`
- `dashboard-sa@cartographie-data-engineer.iam.gserviceaccount.com`

Accès minimal lecture secret pour l’ingestion :

```bash
docker compose run --rm infra-iac gcloud secrets add-iam-policy-binding FT_CLIENT_ID \
  --member="serviceAccount:ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project cartographie-data-engineer

docker compose run --rm infra-iac gcloud secrets add-iam-policy-binding FT_CLIENT_SECRET \
  --member="serviceAccount:ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project cartographie-data-engineer

docker compose run --rm infra-iac gcloud secrets add-iam-policy-binding DATAGOUV_API_KEY \
  --member="serviceAccount:ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project cartographie-data-engineer
```

---

## 5) Vérifier que tout est OK

Lister les secrets :

```bash
docker compose run --rm infra-iac gcloud secrets list --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets versions list FT_CLIENT_ID --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets versions list FT_CLIENT_SECRET --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets versions list DATAGOUV_API_KEY --project cartographie-data-engineer
```

Lire la dernière version (test) :

```bash
docker compose run --rm infra-iac gcloud secrets versions access latest --secret=FT_CLIENT_ID --project cartographie-data-engineer
```

---

## 6) Erreurs fréquentes

### `PERMISSION_DENIED` à la création des secrets
Vous n’avez pas les rôles IAM nécessaires. Voir étape 2.

### `API [secretmanager.googleapis.com] not enabled`
Refaire étape 1.

### Impossible d’utiliser les secrets depuis le runtime
Le service account runtime n’a pas `roles/secretmanager.secretAccessor` sur le secret. Voir étape 4.

### `INVALID_ARGUMENT: Secret Payload cannot be empty`
La version a été ajoutée avec une valeur vide. Refaire l’étape 3.2 avec `bash -lc` (ou l’alternative fichier) puis vérifier avec `gcloud secrets versions list`.

---

## 7) Bonnes pratiques sécurité

- Ne jamais commiter de secrets dans `.env`, `terraform.tfvars` ou le code.
- Garder `.env` local uniquement (déjà ignoré par `.gitignore`).
- Utiliser Secret Manager + IAM (principe du moindre privilège).
- Tourner les secrets régulièrement (nouvelle version).
