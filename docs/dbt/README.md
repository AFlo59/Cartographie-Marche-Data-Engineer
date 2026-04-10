# Documentation dbt - Transformation

Ce dossier contient la documentation operationnelle du projet dbt (BigQuery sur GCP), structuree comme la documentation infra racine.

## Point d'entree

- `setup_guide.md` : guide principal et ordre recommande

## Guides operationnels

- `gcp_manual_setup.md` : prerequis GCP a faire une fois en amont
- `local_run_commands.md` : execution dbt avec installation locale
- `docker_run_commands.md` : execution dbt via Docker Compose
- `dbt_setup.md` : guide rapide (resume)

## Convention recommandee

- Tout nouveau modele SQL doit avoir une documentation YAML associee.
- Les tests qualite doivent etre versionnes avec les modeles.
- Les changements de configuration dbt (`dbt_project.yml`, `profiles.yml`) doivent etre documentes dans ce dossier.
