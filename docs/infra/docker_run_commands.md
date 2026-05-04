# Commandes Docker — workflow infra récurrent

Ce guide couvre uniquement l'exécution Terraform via le conteneur `infra-iac`.

Pour le setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)

Pour la vue d'ensemble : [docs/setup_guide.md](../setup_guide.md)

> Ce guide sert principalement au **développement local**, à la validation manuelle et au debug.
> Dans le périmètre actuel, le **déploiement principal de l'infrastructure Terraform** doit passer par GitHub Actions après merge sur `main`.

## Quand utiliser ce fichier

Utiliser ce guide pour les opérations récurrentes :

- build de l'image infra,
- authentification locale,
- `init`, `validate`, `plan`, `apply`,
- vérifications après déploiement.

Les opérations sensibles ou one-shot ont leur guide dédié :

- secrets : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)
- IAM : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- WIF GitHub : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)

---

## Ordre recommandé

### 0. Pré-requis

- Le setup GCP manuel est terminé.
- Le fichier `.env` existe et est renseigné (copier depuis `.env.example` si absent).
- Les `TF_VAR_*` nécessaires sont renseignés dans `.env`.

Depuis la racine du repo :

```bash
ls -l .env
# Si absent :
cp .env.example .env
```

### 1. Construire l'image infra

```bash
docker compose build --no-cache infra-iac
```

Pourquoi : reconstruit l'image qui contient `terraform`, `tofu` et `gcloud`.

### 2. Choisir un mode d'authentification local

#### Option A — ADC recommandé

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac gcloud config set project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

Pourquoi : mode standard local quand les clés JSON sont bloquées.

#### Option B — OAuth fallback

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud config set project ${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud auth list
```

Puis utiliser le wrapper intégré :

```bash
docker compose run --rm infra-iac terraform-oauth init -reconfigure
docker compose run --rm infra-iac terraform-oauth validate
docker compose run --rm infra-iac terraform-oauth plan
docker compose run --rm infra-iac terraform-oauth apply
```

Pourquoi : `terraform-oauth` rafraîchit automatiquement le token OAuth avant chaque commande.

### 3. Initialiser Terraform

#### Backend local temporaire

```bash
docker compose run --rm infra-iac terraform init -backend=false
```

Pourquoi : utile pour valider la config sans toucher au backend GCS.

#### Backend GCS réel

```bash
# Le nom du bucket tfstate est défini dans TF_BACKEND_BUCKET (.env ou workflow)
# Convention : datatalent-tfstate-<project_id>
docker compose run --rm infra-iac terraform init -reconfigure
```

Si vous migrez un state local existant vers GCS :

```bash
docker compose run --rm infra-iac terraform init -migrate-state
```

### 4. Vérifier la configuration avant déploiement

```bash
docker compose run --rm infra-iac terraform fmt -check -recursive
docker compose run --rm infra-iac terraform validate
docker compose run --rm infra-iac terraform plan
```

### 5. Appliquer l'infrastructure

```bash
docker compose run --rm infra-iac terraform apply
```

### 6. Vérifier le résultat côté GCP

```bash
docker compose run --rm infra-iac gcloud storage buckets list --project=${GCP_PROJECT_ID}
docker compose run --rm infra-iac bq ls --project_id=${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud run jobs list --region=${GCP_REGION:-us-central1} --project=${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud scheduler jobs list --location=${GCP_REGION:-us-central1} --project=${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud secrets list --project=${GCP_PROJECT_ID}
docker compose run --rm infra-iac gcloud artifacts repositories list --location=${GCP_REGION:-us-central1} --project=${GCP_PROJECT_ID}
```

Pourquoi : confirme bucket, datasets, Cloud Run Jobs, Schedulers, secrets et Artifact Registry.

### 7. Détruire les ressources si nécessaire

```bash
docker compose run --rm infra-iac terraform destroy
```

---

## Commandes utiles par objectif

### Vérifier les versions d'outils du conteneur

```bash
docker compose run --rm infra-iac terraform version
docker compose run --rm infra-iac gcloud --version
```

### Chaîne rapide `init + validate + fmt`

```bash
docker compose run --rm infra-iac sh -lc 'terraform init -backend=false && terraform validate && terraform fmt -check -recursive'
```

### Plan/apply avec wrapper OAuth

```bash
docker compose run --rm infra-iac terraform-oauth plan
docker compose run --rm infra-iac terraform-oauth apply
```

---

## Dépannage rapide

### Le fichier ADC n'existe pas

```bash
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

### Erreur de credentials persistante

Basculer temporairement sur l'option OAuth :

```bash
docker compose run --rm infra-iac terraform-oauth plan
```

### Créer ou peupler les secrets

Guide dédié : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)

---

## Déclencher le Cloud Run Job ingestion via Docker

```bash
GCP_PROJECT_ID="$(docker compose run --rm infra-iac gcloud config get project 2>/dev/null)"
GCP_REGION="${GCP_REGION:-us-central1}"
JOB_NAME="${TF_VAR_compute_job_name:-datatalent-ingestion-job}"

# France Travail
docker compose run --rm infra-iac gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=france_travail

# APEC
docker compose run --rm infra-iac gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=apec

# Jooble
docker compose run --rm infra-iac gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=jooble

# Sirene
docker compose run --rm infra-iac gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=sirene

# Géo
docker compose run --rm infra-iac gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=geo
```

---

## Vérifier les fichiers dans le bucket raw

```bash
RAW_BUCKET="${INGESTION_RAW_BUCKET}"

docker compose run --rm infra-iac gcloud storage ls \
  gs://${RAW_BUCKET}/raw/sirene/ \
  --project=${GCP_PROJECT_ID}

docker compose run --rm infra-iac gcloud storage ls \
  gs://${RAW_BUCKET}/raw/france_travail/ \
  --project=${GCP_PROJECT_ID}

docker compose run --rm infra-iac gcloud storage ls \
  gs://${RAW_BUCKET}/raw/geo/ \
  --project=${GCP_PROJECT_ID}
```

---

## Activer les External Tables BigQuery après la première ingestion

Une fois des fichiers Parquet présents dans le bucket, les External Tables peuvent être créées.
En CI, `TF_VAR_create_external_tables=true` est déjà actif — le prochain `terraform apply` les crée.

Pour forcer localement :

```bash
docker compose run --rm infra-iac terraform apply -var="create_external_tables=true"
```

Vérifier les tables créées :

```bash
docker compose run --rm infra-iac bq ls --project_id=${GCP_PROJECT_ID} raw
docker compose run --rm infra-iac bq show --project_id=${GCP_PROJECT_ID} raw.sirene_etablissements
docker compose run --rm infra-iac bq show --project_id=${GCP_PROJECT_ID} raw.sirene_unites_legales
docker compose run --rm infra-iac bq show --project_id=${GCP_PROJECT_ID} raw.france_travail_offres
```

---

## Options avancées

- Gestion des secrets runtime : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)
- Préparer la CI GitHub Actions : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)
- Vérifier les rôles IAM : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- Commandes sans Docker : [docs/infra/manual_commands.md](../infra/manual_commands.md)
