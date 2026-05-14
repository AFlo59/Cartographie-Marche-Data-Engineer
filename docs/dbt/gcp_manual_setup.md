# Setup manuel GCP en amont pour dbt

Ce guide couvre uniquement les étapes manuelles à faire une fois pour permettre à dbt de se connecter à BigQuery.

## Prérequis

- Projet GCP actif
- APIs activées : BigQuery API
- `gcloud` installé (ou Cloud Shell)
- permissions suffisantes sur BigQuery (lecture/écriture selon usage)

## 1. Sélectionner le projet

```bash
# Remplacer par votre project ID
PROJECT_ID="votre-projet-gcp"
gcloud config set project ${PROJECT_ID}
```

## 2. Authentification locale (ADC)

Mode recommandé pour `DBT_TARGET=dev` (profiles.yml en oauth) :

```bash
gcloud auth application-default login
```

Vérifier le fichier ADC :

```bash
gcloud auth application-default print-access-token
```

## 3. Vérifier l'accès BigQuery

```bash
bq ls --project_id=${PROJECT_ID}
```

## 4. Vérifier les variables attendues par dbt

Dans le `.env` racine (ou variables exportées), vérifier au minimum :

- `GCP_PROJECT_ID` (ex: `cartographie-data-engineer`)
- `GCP_LOCATION` — **utiliser `us-central1`** (bucket raw et Artifact Registry migrés en mai 2026 ; la valeur par défaut du profil `EU` n'est plus correcte)
- `DBT_BIGQUERY_PROJECT`
- `DBT_BIGQUERY_DATASET`
- `DBT_TARGET` (`dev` ou `ci`)

## 5. Cas CI / Cloud Run Job

### GitHub Actions (dbt-ci.yml)

Les workflows GitHub Actions utilisent **Workload Identity Federation (WIF)** — pas de JSON de compte de service.
L'ADC est injecté automatiquement par l'action `google-github-actions/auth`.

### Cloud Run Job (production)

Le Cloud Run Job `datatalent-dbt-job` s'exécute avec le compte de service `dbt-sa`.
L'ADC est fourni automatiquement par la métadonnée d'instance GCP — aucune variable `GOOGLE_APPLICATION_CREDENTIALS` nécessaire.

Ne jamais versionner un JSON de compte de service dans le repo.
