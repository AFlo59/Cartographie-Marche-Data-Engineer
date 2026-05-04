# Exécuter dbt via Docker Compose

Ce guide couvre l'exécution dbt avec le service Docker `dbt` défini à la racine du projet.

## Prérequis

- Docker Desktop / Docker Engine
- Docker Compose
- `.env` racine renseigné à partir de `.env.example`
- authentification GCP valide (ADC ou keyfile selon cible)

## 1. Builder l'image dbt

Depuis la racine du repo :

```bash
docker compose --profile dbt build dbt
```

## 2. Vérifier la configuration dbt

```bash
docker compose --profile dbt run --rm dbt dbt --version
docker compose --profile dbt run --rm dbt dbt debug
docker compose --profile dbt run --rm dbt dbt parse
```

## 3. Exécuter run et tests

```bash
docker compose --profile dbt run --rm dbt dbt run
docker compose --profile dbt run --rm dbt dbt test
```

## 4. Générer et servir la doc dbt

```bash
docker compose --profile dbt run --rm dbt dbt docs generate
docker compose --profile dbt run --rm --service-ports dbt dbt docs serve --port 8080
```

## 5. Cibles dev et ci

- `DBT_TARGET=dev` : méthode oauth (ADC) — usage local
- `DBT_TARGET=ci` : méthode oauth (ADC via metadata server) — usage GitHub Actions / Cloud Run Job

## 6. Dépannage rapide

- erreur d'authentification : vérifier `GOOGLE_APPLICATION_CREDENTIALS` et ADC
- erreur dataset : vérifier `DBT_BIGQUERY_PROJECT`, `DBT_BIGQUERY_DATASET`, `DBT_BIGQUERY_LOCATION`
- profil introuvable : vérifier `DBT_PROFILES_DIR=/app` dans l'image et `profiles.yml` dans `dbt/transformation`
