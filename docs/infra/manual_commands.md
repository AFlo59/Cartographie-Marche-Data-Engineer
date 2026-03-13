# Commandes locales — sans Docker

Ce guide couvre l'exécution Terraform avec les outils installés directement sur votre poste.

Pour le setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)

Pour l'exécution via conteneur : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)

> Ce guide sert principalement au **développement local**, à la validation manuelle et au debug.
> Dans le périmètre actuel, le **déploiement principal de l'infrastructure Terraform** doit passer par GitHub Actions après merge sur `main`.

## Quand utiliser ce fichier

Utiliser ce guide si vous avez installé localement :
- `gcloud`,
- `terraform` ou `tofu`,
- et éventuellement Python pour le projet.

Si ce n'est pas le cas, préférez le guide Docker.

Ce guide couvre uniquement l'exécution manuelle de l'infra pendant le développement, pas la release automatique complète du projet.

## Pré-requis

### 1. Se placer à la racine du projet

```powershell
Set-Location "C:\CHEMIN\VERS\Cartographie-Marche-Data-Engineer"
```

Pourquoi : toutes les commandes supposent la racine du repo comme point de départ.

Placeholder utilisé :
- `C:\CHEMIN\VERS\Cartographie-Marche-Data-Engineer` = chemin local réel du repo sur votre poste.

### 2. Vérifier ou créer `.env`

```powershell
Copy-Item .\.env.example .\.env -ErrorAction SilentlyContinue
Get-Content .\.env
```

Pourquoi : vérifier les variables projet, région, comptes de service et image Cloud Run.

### 3. Authentifier `gcloud`

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project cartographie-data-engineer
gcloud auth list
```

Pourquoi : Terraform Google utilisera ADC en local.

## Workflow Terraform local

### 4. Aller dans le dossier infra

```powershell
Set-Location .\infra
```

Pourquoi : les commandes Terraform doivent partir du dossier contenant les fichiers `.tf`.

### 5. Initialiser Terraform

#### Validation locale simple

```powershell
terraform init -backend=false
```

#### Backend GCS réel

Depuis le dossier `infra/`, récupérez le nom du bucket (défini dans le workflow) :

```powershell
# Exemple: datatalent-tfstate-my-gcp-project-id
terraform init -backend-config="bucket=${TERRAFORM_STATE_BUCKET}" -reconfigure
```

Si migration de state depuis local vers GCS:

```powershell
terraform init -backend-config="bucket=${TERRAFORM_STATE_BUCKET}" -migrate-state
```

Où `${TERRAFORM_STATE_BUCKET}` = nom du bucket de state Terraform (ex: `datatalent-tfstate-my-gcp-project-id`)

### 6. Vérifier la configuration

```powershell
terraform fmt -check -recursive
terraform validate
terraform plan
```

Pourquoi : contrôle style, validité et diff avant application.

### 7. Appliquer

```powershell
terraform apply
```

Pourquoi : crée ou met à jour l'infrastructure dans GCP.

## Gérer une erreur `409 already exists` (drift d'état)

Quand Terraform tente de créer une ressource qui existe déjà dans GCP, il faut **adopter la ressource dans le state** avec `terraform import`.

### Règle de décision

- Ressource existe dans GCP et doit rester gérée par Terraform ? **import**.
- Ressource existe mais configuration Terraform doit changer ? **import**, puis `terraform plan/apply` pour converger.
- Ressource existe mais ne doit pas être gérée par ce state ? ne pas importer (ou `terraform state rm` si déjà importée).
- Ressource créée hors-plan et inutile ? suppression manuelle possible, **uniquement** si impact maîtrisé.

### Important

- Ne jamais supprimer un bucket sensible (ex: bucket backend tfstate) sans plan de migration/backup.
- Ne pas importer le bucket backend tfstate dans le state de cette stack applicative.

### Imports utiles pour ce projet

```powershell
# Depuis le dossier infra/
terraform import module.storage.google_storage_bucket.raw datatalent-dev-cartographie-data-engineer-raw

terraform import module.warehouse.google_bigquery_dataset.raw cartographie-data-engineer:raw
terraform import module.warehouse.google_bigquery_dataset.staging cartographie-data-engineer:staging
terraform import module.warehouse.google_bigquery_dataset.marts cartographie-data-engineer:marts

terraform import 'module.secrets.google_secret_manager_secret.secrets["FT_CLIENT_ID"]' projects/cartographie-data-engineer/secrets/FT_CLIENT_ID
terraform import 'module.secrets.google_secret_manager_secret.secrets["FT_CLIENT_SECRET"]' projects/cartographie-data-engineer/secrets/FT_CLIENT_SECRET
terraform import 'module.secrets.google_secret_manager_secret.secrets["DATAGOUV_API_KEY"]' projects/cartographie-data-engineer/secrets/DATAGOUV_API_KEY
```

Puis revalider :

```powershell
terraform plan
terraform apply
```

### 8. Vérifier les ressources déployées

```powershell
gcloud storage buckets list --project cartographie-data-engineer
bq ls --project_id=cartographie-data-engineer
gcloud run jobs list --region=europe-west1 --project cartographie-data-engineer
gcloud scheduler jobs list --location=europe-west1 --project cartographie-data-engineer
gcloud secrets list --project cartographie-data-engineer
```

Pourquoi : confirme les ressources principales après déploiement.

### 9. Détruire si nécessaire

```powershell
terraform destroy
```

## Dépendances Python du projet

Si vous exécutez aussi les scripts Python localement :

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r ..\requirements.txt
```

Pourquoi : prépare un environnement local pour les scripts d'ingestion.

## Activer le Cloud Run Job après le premier push d'image

Le Cloud Run Job et les Schedulers sont désactivés par défaut (`create_compute_job = false`)
car GCP échoue avec 403 si l'image n'existe pas encore dans Artifact Registry.

### Étape 1 — Builder et pusher l'image d'ingestion

```powershell
# Depuis la racine du repo
docker compose build ingestion

# Authentifier Docker sur Artifact Registry
gcloud auth configure-docker europe-west1-docker.pkg.dev

# Tagger et pousser l'image
docker tag datatalent-ingestion europe-west1-docker.pkg.dev/cartographie-data-engineer/datatalent/ingestion:latest
docker push europe-west1-docker.pkg.dev/cartographie-data-engineer/datatalent/ingestion:latest

# Vérifier la présence de l'image
gcloud artifacts docker images list europe-west1-docker.pkg.dev/cartographie-data-engineer/datatalent --project cartographie-data-engineer
```

### Étape 2 — Activer le job dans Terraform

```powershell
# Depuis le dossier infra/
terraform apply -var="create_compute_job=true"
```

Ou via la CI : mettre `TF_VAR_create_compute_job: "true"` dans `.github/workflows/infra-deploy.yml` puis merger sur `main`.

### Vérifier le job créé

```powershell
gcloud run jobs list --region=europe-west1 --project cartographie-data-engineer
gcloud scheduler jobs list --location=europe-west1 --project cartographie-data-engineer
```

---

## Activer les External Tables BigQuery après la première ingestion

Les External Tables BQ (raw ? GCS) sont désactivées par défaut (`create_external_tables = false`)
car BigQuery refuse de créer une table avec `autodetect = true` si aucun fichier Parquet n'existe encore dans le bucket.

### Prérequis

Vérifier que le bucket contient au moins un fichier Parquet pour chaque source :

```powershell
# Vérifier la présence de fichiers
gcloud storage ls gs://datatalent-dev-cartographie-data-engineer-raw/raw/sirene/ --project cartographie-data-engineer
gcloud storage ls gs://datatalent-dev-cartographie-data-engineer-raw/raw/france_travail/ --project cartographie-data-engineer
```

### Option A — Après un premier run d'ingestion (recommandé)

Déclencher manuellement le Cloud Run Job d'ingestion pour chaque source :

```powershell
# France Travail
gcloud run jobs execute datatalent-ingestion-job \
  --region=europe-west1 \
  --project cartographie-data-engineer \
  --update-env-vars INGESTION_SOURCE=france_travail

# Sirene
gcloud run jobs execute datatalent-ingestion-job \
  --region=europe-west1 \
  --project cartographie-data-engineer \
  --update-env-vars INGESTION_SOURCE=sirene
```

Suivre l'exécution :

```powershell
gcloud run jobs executions list \
  --job=datatalent-ingestion-job \
  --region=europe-west1 \
  --project cartographie-data-engineer
```

### Option B — Fichier placeholder minimal (test rapide, hors production)

Créer un fichier Parquet vide ou minimal avec Python, puis l'uploader :

```powershell
# Installer pyarrow si nécessaire
pip install pyarrow

# Créer un placeholder Parquet vide
python -c "import pyarrow as pa; import pyarrow.parquet as pq; pq.write_table(pa.table({'_placeholder': pa.array([], type=pa.string())}), 'placeholder.parquet')"

# Uploader dans les deux prefixes
gcloud storage cp placeholder.parquet \
  gs://datatalent-dev-cartographie-data-engineer-raw/raw/sirene/etablissements/placeholder.parquet \
  --project cartographie-data-engineer

gcloud storage cp placeholder.parquet \
  gs://datatalent-dev-cartographie-data-engineer-raw/raw/sirene/unites_legales/placeholder.parquet \
  --project cartographie-data-engineer

gcloud storage cp placeholder.parquet \
  gs://datatalent-dev-cartographie-data-engineer-raw/raw/france_travail/placeholder.parquet \
  --project cartographie-data-engineer
```

### Activer les External Tables (après que les fichiers existent)

```powershell
# Depuis le dossier infra/
terraform apply -var="create_external_tables=true"
```

Ou via la CI : mettre `TF_VAR_create_external_tables: "true"` dans `.github/workflows/infra-deploy.yml`
puis merger sur `main`.

### Vérifier les tables créées

```powershell
bq ls --project_id=cartographie-data-engineer raw
bq show --project_id=cartographie-data-engineer raw.sirene_etablissements
bq show --project_id=cartographie-data-engineer raw.sirene_unites_legales
bq show --project_id=cartographie-data-engineer raw.france_travail_offres
```

---

## Options avancées

### Vous voulez gérer les secrets runtime

Utiliser le guide dédié : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)

### Vous préparez la CI GitHub Actions

Utiliser le guide dédié : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)

### Vous voulez vérifier les rôles IAM

Utiliser le guide dédié : [docs/infra/iam_roles.md](../infra/iam_roles.md)
