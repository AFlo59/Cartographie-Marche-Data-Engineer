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

- `GCP_PROJECT_ID`
- `GCP_LOCATION` (ex: `EU`)
- `DBT_BIGQUERY_PROJECT`
- `DBT_BIGQUERY_DATASET`
- `DBT_TARGET` (`dev` ou `ci`)

## 5. Cas CI / compte de service

Pour `DBT_TARGET=ci`, le profil attend :

- `GOOGLE_APPLICATION_CREDENTIALS` pointe vers un fichier JSON valide
- le compte de service dispose des rôles BigQuery nécessaires

Ne jamais versionner le JSON de compte de service dans le repo.
