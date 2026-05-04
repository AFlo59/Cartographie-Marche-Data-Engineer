# Guide pas  pas  Secret Manager runtime (INFRA-06)

Ce guide traite uniquement la partie Secret Manager runtime : cration des conteneurs, ajout des versions relles, bindings IAM et vrifications.

Prrequis dj documents ailleurs :
- setup manuel GCP : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- excution Docker et authentification locale : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- matrice complte des rles : [docs/infra/iam_roles.md](../infra/iam_roles.md)

> Ce guide sert  prparer les secrets runtime pour le dveloppement et pour la plateforme.
> Le dploiement principal de l'infrastructure reste pilot par GitHub Actions.

---

## Variables a definir

Definir ces variables dans le shell avant d'executer les commandes de ce guide (y compris celles via `docker compose run`) :

```bash
GCP_PROJECT_ID="your-gcp-project-id"   # identifiant de votre projet GCP  <- a renseigner
USER_EMAIL="your-email@domain.com"      # email de votre compte utilisateur <- a renseigner

# Service accounts (construits a partir de GCP_PROJECT_ID)
INGESTION_SA="ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
```

## 0) Prrequis

- Le projet GCP est dj prpar.
- L'authentification `gcloud` fonctionne dj dans le contexte utilis.
- Les rles IAM ncessaires sont dj attribus.

Ce guide part du principe que vous avez dj suivi les guides prcdents.

---

## 1) Vrifier le contexte et l'API

```bash
docker compose run --rm infra-iac gcloud config set project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud config get-value project
docker compose run --rm infra-iac gcloud services list --enabled --filter="name:secretmanager.googleapis.com"
```

Rsultat attendu : projet actif `${GCP_PROJECT_ID}` et API Secret Manager active.

Si l'API n'est pas active :

```bash
docker compose run --rm infra-iac gcloud services enable secretmanager.googleapis.com --project ${GCP_PROJECT_ID}
```

---

## 2) Vrifier les permissions IAM (cause la plus frquente)

Pour crer des secrets, il faut au minimum un rle contenant :
- `secretmanager.secrets.create`
- `secretmanager.versions.add`

Rles pratiques :
- `roles/secretmanager.admin` (admin complet)
- ou combinaison custom plus restrictive.

Diagnostic rapide :

```bash
docker compose run --rm infra-iac gcloud projects get-iam-policy ${GCP_PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:user:${USER_EMAIL}" --format="table(bindings.role)"
```

Si vous navez pas les rles requis, demandez  un admin projet dexcuter :

```bash
docker compose run --rm infra-iac gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} --member="user:${USER_EMAIL}" --role="roles/secretmanager.admin"
```

Note PowerShell : utilisez la commande sur **une seule ligne** (pas de `\` de continuation shell).

Placeholders utiliss dans cette section :
- `${USER_EMAIL}` = email de l'utilisateur humain auquel on veut donner un rle projet.

Note : si la commande de diagnostic affiche dj `roles/owner` ou `roles/secretmanager.admin`, vous avez dj les droits ncessaires et vous pouvez passer  ltape 3.

---

## 3) Crer les secrets (sans exposer les valeurs dans lhistorique shell)

Secrets backlog INFRA-06 :
- `FT_CLIENT_ID`
- `FT_CLIENT_SECRET`

Secrets projet recommands (scope actuel infra/ingestion) :
- `FT_CLIENT_ID` (obligatoire)
- `FT_CLIENT_SECRET` (obligatoire)
- `DATAGOUV_API_KEY` (optionnel, seulement si activation d'auth ct data.gouv.fr)

Note importante (bucket raw INFRA-02) : laccs au bucket se fait par IAM/service account, **pas** par secret `bucket_id/secret`.
Le compte `ingestion-sa` doit avoir les rles GCS ncessaires (INFRA-07).

### 3.1 Crer les conteneurs de secrets

Si vous avez dj excut `terraform apply` avec le module secrets, cette tape peut dj tre faite. Sinon, crez les conteneurs manuellement.

```bash
docker compose run --rm infra-iac gcloud secrets create FT_CLIENT_ID --replication-policy="automatic" --project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud secrets create FT_CLIENT_SECRET --replication-policy="automatic" --project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud secrets create DATAGOUV_API_KEY --replication-policy="automatic" --project ${GCP_PROJECT_ID}
```

Si un secret existe dj, ignorer lerreur `ALREADY_EXISTS`.

### 3.2 Ajouter une version (valeur)

Option sre (interactif, sans mettre la valeur en clair dans la commande) :

```bash
docker compose run --rm -it infra-iac bash -lc 'read -rsp "FT_CLIENT_ID: " FTID; echo; printf "%s" "$FTID" | gcloud secrets versions add FT_CLIENT_ID --data-file=- --project ${GCP_PROJECT_ID}'

docker compose run --rm -it infra-iac bash -lc 'read -rsp "FT_CLIENT_SECRET: " FTSEC; echo; printf "%s" "$FTSEC" | gcloud secrets versions add FT_CLIENT_SECRET --data-file=- --project ${GCP_PROJECT_ID}'

docker compose run --rm -it infra-iac bash -lc 'read -rsp "DATAGOUV_API_KEY (optionnel): " DGKEY; echo; printf "%s" "$DGKEY" | gcloud secrets versions add DATAGOUV_API_KEY --data-file=- --project ${GCP_PROJECT_ID}'
```

Pourquoi : `sh` (dash) ne supporte pas `read -s`, d'o l'erreur `Illegal option -s`. Utiliser `bash` corrige ce point.

Alternative non interactive (fichier local temporaire, puis suppression) :

```bash
docker compose run --rm infra-iac sh -lc 'printf "%s" "VOTRE_FT_CLIENT_ID" > /tmp/ft_client_id.txt; gcloud secrets versions add FT_CLIENT_ID --data-file=/tmp/ft_client_id.txt --project ${GCP_PROJECT_ID}; rm -f /tmp/ft_client_id.txt'
docker compose run --rm infra-iac sh -lc 'printf "%s" "VOTRE_FT_CLIENT_SECRET" > /tmp/ft_client_secret.txt; gcloud secrets versions add FT_CLIENT_SECRET --data-file=/tmp/ft_client_secret.txt --project ${GCP_PROJECT_ID}; rm -f /tmp/ft_client_secret.txt'
docker compose run --rm infra-iac sh -lc 'printf "%s" "VOTRE_DATAGOUV_API_KEY" > /tmp/datagouv_api_key.txt; gcloud secrets versions add DATAGOUV_API_KEY --data-file=/tmp/datagouv_api_key.txt --project ${GCP_PROJECT_ID}; rm -f /tmp/datagouv_api_key.txt'
```

Placeholders utiliss dans cette section :
- `VOTRE_FT_CLIENT_ID` = identifiant OAuth2 de l'application France Travail.
- `VOTRE_FT_CLIENT_SECRET` = secret OAuth2 de l'application France Travail.
- `VOTRE_DATAGOUV_API_KEY` = cl API Data Gouv si vous utilisez cette source avec authentification.

---

## 4) Donner laccs aux Service Accounts applicatifs

Daprs votre `.env` actuel, principaux comptes :
- `ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
- `dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
- `dashboard-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`

Accs minimal lecture secret pour lingestion :

```bash
docker compose run --rm infra-iac gcloud secrets add-iam-policy-binding FT_CLIENT_ID \
  --member="serviceAccount:ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project ${GCP_PROJECT_ID}

docker compose run --rm infra-iac gcloud secrets add-iam-policy-binding FT_CLIENT_SECRET \
  --member="serviceAccount:ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project ${GCP_PROJECT_ID}

docker compose run --rm infra-iac gcloud secrets add-iam-policy-binding DATAGOUV_API_KEY \
  --member="serviceAccount:ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project ${GCP_PROJECT_ID}
```

---

## 5) Vrifier que tout est OK

Lister les secrets :

```bash
docker compose run --rm infra-iac gcloud secrets list --project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud secrets versions list FT_CLIENT_ID --project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud secrets versions list FT_CLIENT_SECRET --project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud secrets versions list DATAGOUV_API_KEY --project ${GCP_PROJECT_ID}
```

Lire la dernire version (test) :

```bash
docker compose run --rm infra-iac gcloud secrets versions access latest --secret=FT_CLIENT_ID --project ${GCP_PROJECT_ID}
```

---

## 6) Erreurs frquentes

### `PERMISSION_DENIED`  la cration des secrets
Vous navez pas les rles IAM ncessaires. Voir tape 2.

### `API [secretmanager.googleapis.com] not enabled`
Refaire tape 1.

### Impossible dutiliser les secrets depuis le runtime
Le service account runtime na pas `roles/secretmanager.secretAccessor` sur le secret. Voir tape 4.

### `INVALID_ARGUMENT: Secret Payload cannot be empty`
La version a t ajoute avec une valeur vide. Refaire ltape 3.2 avec `bash -lc` (ou lalternative fichier) puis vrifier avec `gcloud secrets versions list`.

---

## 7) Bonnes pratiques scurit

- Ne jamais commiter de secrets dans `.env`, `terraform.tfvars` ou le code.
- Garder `.env` local uniquement (dj ignor par `.gitignore`).
- Utiliser Secret Manager + IAM (principe du moindre privilge).
- Tourner les secrets rgulirement (nouvelle version).
