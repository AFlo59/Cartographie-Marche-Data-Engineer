# Setup dbt BigQuery (GCP)

Ce document reste un resume rapide.
Pour un parcours complet et ordonne (amont GCP, setup local, run local, run Docker), utiliser :

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

## Raccourci commandes locales

Depuis `dbt/transformation` :

```bash
dbt debug --profiles-dir .
dbt parse --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
```
