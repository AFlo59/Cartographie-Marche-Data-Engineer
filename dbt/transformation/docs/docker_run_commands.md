# Run dbt via Docker Compose

Ce guide couvre l'execution dbt avec le service Docker `dbt` defini a la racine du projet.

## Prerequis

- Docker Desktop / Docker Engine
- Docker Compose
- `.env` racine renseigne a partir de `.env.example`
- authentification GCP valide (ADC ou keyfile selon cible)

## 1. Build l'image dbt

Depuis la racine du repo :

```bash
docker compose --profile dbt build dbt
```

## 2. Verifier la configuration dbt

```bash
docker compose --profile dbt run --rm dbt dbt --version
docker compose --profile dbt run --rm dbt dbt debug
docker compose --profile dbt run --rm dbt dbt parse
```

## 3. Executer run et tests

```bash
docker compose --profile dbt run --rm dbt dbt run
docker compose --profile dbt run --rm dbt dbt test
```

## 4. Generer et servir la doc dbt

```bash
docker compose --profile dbt run --rm dbt dbt docs generate
docker compose --profile dbt run --rm --service-ports dbt dbt docs serve --port 8080
```

## 5. Cibles dev et ci

- `DBT_TARGET=dev` : methode oauth (ADC)
- `DBT_TARGET=ci` : methode service-account, `GOOGLE_APPLICATION_CREDENTIALS` requis

## 6. Depannage rapide

- erreur d'authentification : verifier `GOOGLE_APPLICATION_CREDENTIALS` et ADC
- erreur dataset : verifier `DBT_BIGQUERY_PROJECT`, `DBT_BIGQUERY_DATASET`, `DBT_BIGQUERY_LOCATION`
- profil introuvable : verifier `DBT_PROFILES_DIR=/app` dans l'image et `profiles.yml` dans `dbt/transformation`