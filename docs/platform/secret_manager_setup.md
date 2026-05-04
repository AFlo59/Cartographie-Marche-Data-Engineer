# Guide pas à pas — Secret Manager runtime (INFRA-06)

Ce guide traite uniquement la partie Secret Manager runtime : création des conteneurs, ajout des versions réelles, bindings IAM et vérifications.

Prérequis déjà documentés ailleurs :

- setup manuel GCP : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- exécution Docker et authentification locale : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- matrice complète des rôles : [docs/infra/iam_roles.md](../infra/iam_roles.md)

> Ce guide sert à préparer les secrets runtime pour le développement et pour la plateforme.
> Le déploiement principal de l'infrastructure reste piloté par GitHub Actions.

---

## Variables de configuration

Définir ces variables **une seule fois** avant d'exécuter les commandes de ce guide :

```bash
# ═══════════════════════════════════════════════════════════════
# Variables — adapter à votre projet avant d'exécuter ce guide
# ═══════════════════════════════════════════════════════════════
PROJECT_ID="votre-projet-gcp"              # ← ID de votre projet GCP

# Compte de service applicatif qui lit les secrets au runtime
INGESTION_SA="ingestion-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

---

## 0) Prérequis

- Le projet GCP est déjà préparé.
- L'authentification `gcloud` fonctionne déjà dans le contexte utilisé.
- Les rôles IAM nécessaires sont déjà attribués.

Ce guide part du principe que vous avez déjà suivi les guides précédents.

---

## 1) Vérifier le contexte et l'API

```bash
docker compose run --rm infra-iac gcloud config set project ${PROJECT_ID}
docker compose run --rm infra-iac gcloud config get-value project
docker compose run --rm infra-iac gcloud services list --enabled \
  --filter="name:secretmanager.googleapis.com"
```

Résultat attendu : projet actif et API Secret Manager active.

Si l'API n'est pas active :

```bash
docker compose run --rm infra-iac gcloud services enable \
  secretmanager.googleapis.com --project ${PROJECT_ID}
```

---

## 2) Vérifier les permissions IAM

Pour créer des secrets, il faut au minimum :

- `secretmanager.secrets.create`
- `secretmanager.versions.add`

Diagnostic rapide :

```bash
docker compose run --rm infra-iac \
  gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:YOUR_USER_EMAIL" \
  --format="table(bindings.role)"
```

Si vous n'avez pas les rôles requis, demandez à un admin d'exécuter :

```bash
docker compose run --rm infra-iac \
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="user:YOUR_USER_EMAIL" \
  --role="roles/secretmanager.admin"
```

> **Placeholder** : `YOUR_USER_EMAIL` = email de l'utilisateur humain à autoriser.

Note PowerShell : utiliser la commande sur **une seule ligne** (pas de `\` de continuation shell).

Note : si le diagnostic affiche déjà `roles/owner` ou `roles/secretmanager.admin`, vous avez les droits nécessaires — passer à l'étape 3.

---

## 3) Créer les secrets (sans exposer les valeurs dans l'historique shell)

Secrets obligatoires pour l'ingestion France Travail :

- `FT_CLIENT_ID`
- `FT_CLIENT_SECRET`

Secrets supplémentaires :

- `DATAGOUV_API_KEY` (optionnel — seulement si auth côté data.gouv.fr)
- `JOOBLE_API_KEY` (requis pour Jooble)

### 3.1 Créer les conteneurs de secrets

Si `terraform apply` a déjà été exécuté avec le module secrets, cette étape est déjà faite. Sinon, créer manuellement :

```bash
docker compose run --rm infra-iac \
  gcloud secrets create FT_CLIENT_ID \
  --replication-policy="automatic" --project ${PROJECT_ID}

docker compose run --rm infra-iac \
  gcloud secrets create FT_CLIENT_SECRET \
  --replication-policy="automatic" --project ${PROJECT_ID}

docker compose run --rm infra-iac \
  gcloud secrets create DATAGOUV_API_KEY \
  --replication-policy="automatic" --project ${PROJECT_ID}

docker compose run --rm infra-iac \
  gcloud secrets create JOOBLE_API_KEY \
  --replication-policy="automatic" --project ${PROJECT_ID}
```

Si un secret existe déjà, ignorer l'erreur `ALREADY_EXISTS`.

### 3.2 Ajouter les valeurs (interactif — sécurisé)

Option recommandée : saisie interactive sans afficher la valeur en clair.

```bash
docker compose run --rm -it infra-iac bash -lc \
  'read -rsp "FT_CLIENT_ID: " V; echo; printf "%s" "$V" | \
  gcloud secrets versions add FT_CLIENT_ID --data-file=- --project '"${PROJECT_ID}"

docker compose run --rm -it infra-iac bash -lc \
  'read -rsp "FT_CLIENT_SECRET: " V; echo; printf "%s" "$V" | \
  gcloud secrets versions add FT_CLIENT_SECRET --data-file=- --project '"${PROJECT_ID}"

docker compose run --rm -it infra-iac bash -lc \
  'read -rsp "DATAGOUV_API_KEY: " V; echo; printf "%s" "$V" | \
  gcloud secrets versions add DATAGOUV_API_KEY --data-file=- --project '"${PROJECT_ID}"

docker compose run --rm -it infra-iac bash -lc \
  'read -rsp "JOOBLE_API_KEY: " V; echo; printf "%s" "$V" | \
  gcloud secrets versions add JOOBLE_API_KEY --data-file=- --project '"${PROJECT_ID}"
```

Pourquoi `bash -lc` : `sh` (dash) ne supporte pas `read -s`, d'où l'erreur `Illegal option -s`. Utiliser `bash` corrige ce point.

### 3.3 Alternative non interactive (fichier temporaire)

```bash
docker compose run --rm infra-iac sh -lc \
  'printf "%s" "VALEUR_FT_CLIENT_ID" > /tmp/s.txt; \
  gcloud secrets versions add FT_CLIENT_ID --data-file=/tmp/s.txt --project '"${PROJECT_ID}"'; \
  rm -f /tmp/s.txt'
```

> **Placeholders** : remplacer `VALEUR_FT_CLIENT_ID` etc. par les vraies valeurs — ne pas commiter ces commandes avec les valeurs réelles.

---

## 4) Donner l'accès au compte de service ingestion

```bash
for SECRET in FT_CLIENT_ID FT_CLIENT_SECRET DATAGOUV_API_KEY JOOBLE_API_KEY; do
  docker compose run --rm infra-iac \
    gcloud secrets add-iam-policy-binding ${SECRET} \
    --member="serviceAccount:${INGESTION_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --project ${PROJECT_ID}
done
```

---

## 5) Vérifier que tout est OK

```bash
# Lister les secrets
docker compose run --rm infra-iac \
  gcloud secrets list --project ${PROJECT_ID}

# Vérifier les versions
for SECRET in FT_CLIENT_ID FT_CLIENT_SECRET DATAGOUV_API_KEY JOOBLE_API_KEY; do
  docker compose run --rm infra-iac \
    gcloud secrets versions list ${SECRET} --project ${PROJECT_ID}
done

# Lire la dernière version (test)
docker compose run --rm infra-iac \
  gcloud secrets versions access latest \
  --secret=FT_CLIENT_ID --project ${PROJECT_ID}
```

---

## 6) Erreurs fréquentes

### `PERMISSION_DENIED` à la création des secrets

Vous n'avez pas les rôles IAM nécessaires. Voir étape 2.

### `API [secretmanager.googleapis.com] not enabled`

Refaire étape 1.

### Impossible d'utiliser les secrets depuis le runtime

Le compte de service runtime n'a pas `roles/secretmanager.secretAccessor` sur le secret. Voir étape 4.

### `INVALID_ARGUMENT: Secret Payload cannot be empty`

La version a été ajoutée avec une valeur vide. Refaire l'étape 3.2 avec `bash -lc` puis vérifier avec `gcloud secrets versions list`.

---

## 7) Bonnes pratiques sécurité

- Ne jamais commiter de secrets dans `.env`, `terraform.tfvars` ou le code.
- Garder `.env` local uniquement (déjà ignoré par `.gitignore`).
- Utiliser Secret Manager + IAM (principe du moindre privilège).
- Tourner les secrets régulièrement (nouvelle version dans Secret Manager).
