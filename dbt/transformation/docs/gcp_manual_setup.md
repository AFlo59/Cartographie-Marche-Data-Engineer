# Setup manuel GCP en amont pour dbt

Ce guide couvre uniquement les etapes manuelles a faire une fois pour permettre a dbt de se connecter a BigQuery.

## Prerequis

- GCP project actif
- APIs activees : BigQuery API
- `gcloud` installe (ou Cloud Shell)
- permissions suffisantes sur BigQuery (lecture/ecriture selon usage)

## 1. Selectionner le projet

```bash
gcloud config set project <GCP_PROJECT_ID>
```

## 2. Authentification locale (ADC)

Mode recommande pour `DBT_TARGET=dev` (profiles.yml en oauth) :

```bash
gcloud auth application-default login
```

Verifier le fichier ADC :

```bash
gcloud auth application-default print-access-token
```

## 3. Verifier l'acces BigQuery

```bash
bq ls --project_id=<GCP_PROJECT_ID>
```

## 4. Verifier les variables attendues par dbt

Dans le `.env` racine (ou variables exportees), verifier au minimum :

- `GCP_PROJECT_ID`
- `GCP_LOCATION` (ex: `EU`)
- `DBT_BIGQUERY_PROJECT`
- `DBT_BIGQUERY_DATASET`
- `DBT_TARGET` (`dev` ou `ci`)

## 5. Cas CI/service account

Pour `DBT_TARGET=ci`, le profil attend :

- `GOOGLE_APPLICATION_CREDENTIALS` pointe vers un fichier JSON valide
- la SA dispose des roles BigQuery necessaires

Ne jamais versionner le JSON de service account dans le repo.