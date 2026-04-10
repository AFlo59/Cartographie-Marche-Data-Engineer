# Commandes locales sans Docker

Ce guide couvre l'exécution Terraform avec les outils installés directement sur votre poste.

Pour le setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)

Pour l'exécution via conteneur : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)

> Ce guide sert principalement au **développement local**, à la validation manuelle et au debug.
> Dans le périmètre actuel, le **déploiement principal de l'infrastructure Terraform** doit passer par GitHub Actions après merge sur `main`.

## Quand utiliser ce fichier

Utiliser ce guide si vous avez installé localement :

- `gcloud`
- `terraform` ou `tofu`
- et éventuellement Python pour le projet.

Si ce n'est pas le cas, préférez le guide Docker.

---

## Pré-requis

### 1. Se placer à la racine du projet

```bash
cd /chemin/vers/Cartographie-Marche-Data-Engineer
```

Pourquoi : toutes les commandes supposent la racine du repo comme point de départ.

### 2. Vérifier ou créer `.env`

```bash
cp .env.example .env   # si absent
cat .env
```

Pourquoi : vérifier les variables projet, région, comptes de service et image Cloud Run.

### 3. Authentifier `gcloud`

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project ${GCP_PROJECT_ID}   # remplacer par votre project ID
gcloud auth list
```

Pourquoi : Terraform Google utilisera ADC en local.

---

## Workflow Terraform local

### 4. Aller dans le dossier infra

```bash
cd infra
```

### 5. Initialiser Terraform

#### Validation locale simple (sans backend)

```bash
terraform init -backend=false
```

#### Backend GCS réel

Récupérer le nom du bucket tfstate (défini dans le workflow `infra-deploy.yml` via `TF_BACKEND_BUCKET`) :

```bash
# Le nom du bucket tfstate suit la convention : datatalent-tfstate-<project_id>
TF_BACKEND_BUCKET="datatalent-tfstate-${GCP_PROJECT_ID}"

terraform init -backend-config="bucket=${TF_BACKEND_BUCKET}" -reconfigure
```

Si migration de state depuis local vers GCS :

```bash
terraform init -backend-config="bucket=${TF_BACKEND_BUCKET}" -migrate-state
```

### 6. Vérifier la configuration

```bash
terraform fmt -check -recursive
terraform validate
terraform plan
```

### 7. Appliquer

```bash
terraform apply
```

---

## Gérer une erreur `409 already exists` (drift d'état)

Quand Terraform tente de créer une ressource qui existe déjà dans GCP, adopter la ressource dans le state avec `terraform import`.

### Règle de décision

- Ressource existe dans GCP et doit rester gérée par Terraform ? **import**.
- Ressource existe mais configuration doit changer ? **import**, puis `terraform plan/apply`.
- Ressource ne doit pas être gérée par ce state ? ne pas importer (ou `terraform state rm` si déjà importée).

> Ne jamais supprimer un bucket sensible (ex: bucket backend tfstate) sans plan de migration/backup.

### Imports utiles pour ce projet

Depuis le dossier `infra/`, avec les variables chargées depuis `.env` :

```bash
# Charger les variables depuis .env (Linux/Mac)
source ../.env

# Ou définir manuellement
GCP_PROJECT_ID="<votre-project-id>"
TF_BACKEND_BUCKET="datatalent-tfstate-${GCP_PROJECT_ID}"
# Le bucket raw est construit par Terraform — récupérer depuis terraform output ou .env
RAW_BUCKET="${INGESTION_RAW_BUCKET}"

# Bucket raw
terraform import module.storage.google_storage_bucket.raw ${RAW_BUCKET}

# Datasets BigQuery
terraform import module.warehouse.google_bigquery_dataset.raw  projects/${GCP_PROJECT_ID}/datasets/raw
terraform import module.warehouse.google_bigquery_dataset.staging projects/${GCP_PROJECT_ID}/datasets/staging
terraform import module.warehouse.google_bigquery_dataset.marts  projects/${GCP_PROJECT_ID}/datasets/marts

# Secrets Manager
terraform import 'module.secrets.google_secret_manager_secret.secrets["FT_CLIENT_ID"]'     projects/${GCP_PROJECT_ID}/secrets/FT_CLIENT_ID
terraform import 'module.secrets.google_secret_manager_secret.secrets["FT_CLIENT_SECRET"]' projects/${GCP_PROJECT_ID}/secrets/FT_CLIENT_SECRET
terraform import 'module.secrets.google_secret_manager_secret.secrets["DATAGOUV_API_KEY"]' projects/${GCP_PROJECT_ID}/secrets/DATAGOUV_API_KEY

# Artifact Registry
terraform import module.compute.google_artifact_registry_repository.datatalent \
  projects/${GCP_PROJECT_ID}/locations/${GCP_REGION:-europe-west1}/repositories/datatalent

# Cloud Run Jobs
terraform import 'module.compute.google_cloud_run_v2_job.ingestion[0]' \
  projects/${GCP_PROJECT_ID}/locations/${GCP_REGION:-europe-west1}/jobs/${TF_VAR_compute_job_name:-datatalent-ingestion-job}

terraform import 'module.compute.google_cloud_run_v2_job.dbt[0]' \
  projects/${GCP_PROJECT_ID}/locations/${GCP_REGION:-europe-west1}/jobs/${TF_VAR_dbt_job_name:-datatalent-dbt-job}

# Cloud Logging retention
terraform import 'module.compute.google_logging_project_bucket_config.default_retention[0]' \
  projects/${GCP_PROJECT_ID}/locations/global/buckets/_Default

# Cloud Schedulers
SCHEDULER_PREFIX="${TF_VAR_scheduler_job_name_prefix:-datatalent-ingestion}"
for SOURCE in france_travail sirene geo; do
  terraform import "module.scheduler[0].google_cloud_scheduler_job.ingestion[\"${SOURCE}\"]" \
    projects/${GCP_PROJECT_ID}/locations/${GCP_REGION:-europe-west1}/jobs/${SCHEDULER_PREFIX}-${SOURCE}
done
```

Puis revalider :

```bash
terraform plan
terraform apply
```

### 8. Vérifier les ressources déployées

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
GCP_REGION="${GCP_REGION:-europe-west1}"

gcloud storage buckets list --project=${GCP_PROJECT_ID}
bq ls --project_id=${GCP_PROJECT_ID}
gcloud run jobs list --region=${GCP_REGION} --project=${GCP_PROJECT_ID}
gcloud scheduler jobs list --location=${GCP_REGION} --project=${GCP_PROJECT_ID}
gcloud secrets list --project=${GCP_PROJECT_ID}
gcloud artifacts repositories list --location=${GCP_REGION} --project=${GCP_PROJECT_ID}
```

### 9. Détruire si nécessaire

```bash
terraform destroy
```

---

## Dépendances Python du projet

Si vous exécutez aussi les scripts Python localement :

```bash
python -m venv .venv
source .venv/bin/activate   # Linux/Mac
# ou .\.venv\Scripts\Activate.ps1 sous Windows PowerShell
pip install -r requirements.txt
```

---

## Bootstrap Artifact Registry (one-shot avant le premier push CI)

Le repo Artifact Registry est créé par Terraform, mais le CI pousse les images **après** le `terraform apply`.
Si le repo n'existe pas encore, le créer une fois manuellement :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
GCP_REGION="${GCP_REGION:-europe-west1}"
AR_REPO="datatalent"

# Créer le repo Docker dans Artifact Registry
gcloud artifacts repositories create ${AR_REPO} \
  --repository-format=docker \
  --location=${GCP_REGION} \
  --project=${GCP_PROJECT_ID}

# Vérifier
gcloud artifacts repositories describe ${AR_REPO} \
  --location=${GCP_REGION} \
  --project=${GCP_PROJECT_ID}
```

Après cette commande, redéclencher le workflow CI (push ou `workflow_dispatch`).
Terraform importera le repo existant via le step `import_if_needed` au prochain apply.

---

## Déclencher manuellement le Cloud Run Job ingestion

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
GCP_REGION="${GCP_REGION:-europe-west1}"
JOB_NAME="${TF_VAR_compute_job_name:-datatalent-ingestion-job}"

# France Travail
gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=france_travail

# Sirene
gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=sirene

# Géo
gcloud run jobs execute ${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID} \
  --update-env-vars INGESTION_SOURCE=geo

# Suivre l'exécution
gcloud run jobs executions list \
  --job=${JOB_NAME} \
  --region=${GCP_REGION} \
  --project=${GCP_PROJECT_ID}
```

---

## Activer les External Tables BigQuery après la première ingestion

Les External Tables BQ sont créées quand `TF_VAR_create_external_tables=true`.
BigQuery requiert au moins un fichier Parquet dans le bucket pour `autodetect = true`.

### Prérequis — vérifier la présence de fichiers

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
RAW_BUCKET="${INGESTION_RAW_BUCKET}"

gcloud storage ls gs://${RAW_BUCKET}/raw/sirene/ --project=${GCP_PROJECT_ID}
gcloud storage ls gs://${RAW_BUCKET}/raw/france_travail/ --project=${GCP_PROJECT_ID}
gcloud storage ls gs://${RAW_BUCKET}/raw/geo/ --project=${GCP_PROJECT_ID}
```

### Vérifier les External Tables créées

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

bq ls --project_id=${GCP_PROJECT_ID} raw
bq show --project_id=${GCP_PROJECT_ID} raw.sirene_etablissements
bq show --project_id=${GCP_PROJECT_ID} raw.sirene_unites_legales
bq show --project_id=${GCP_PROJECT_ID} raw.france_travail_offres
```

---

## Liens utiles

- IAM : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- Docker infra-iac : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- Secrets runtime : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)
- CI GitHub ↔ GCP (WIF) : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)
