# Setup dbt BigQuery (GCP)

Ce document reste un résumé rapide.
Pour un parcours complet et ordonné (amont GCP, setup local, run local, run Docker), utiliser :

- `setup_guide.md`

## Raccourci commandes Docker

Depuis la racine du repo :

```bash
docker compose --profile dbt build dbt
docker compose --profile dbt run --rm dbt dbt debug
docker compose --profile dbt run --rm dbt dbt parse
docker compose --profile dbt run --rm dbt dbt run
docker compose --profile dbt run --rm dbt dbt test
```

## Build et push de l'image dbt vers Artifact Registry

Depuis la racine du repo :

```bash
# Variables — adapter à votre projet
PROJECT_ID="votre-projet-gcp"
REGION="europe-west1"
DBT_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/datatalent/dbt:latest"

# Auth Docker vers Artifact Registry
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Build image dbt
docker build -f dbt/transformation/Dockerfile -t ${DBT_IMAGE} dbt/transformation

# Push image
docker push ${DBT_IMAGE}
```

Prérequis IAM minimaux pour push :

- `roles/artifactregistry.writer` sur le repository Artifact Registry
- repository Artifact Registry existant (ex: `datatalent`)

## Raccourci commandes locales

Depuis `dbt/transformation` :

```bash
dbt debug --profiles-dir .
dbt parse --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
```
