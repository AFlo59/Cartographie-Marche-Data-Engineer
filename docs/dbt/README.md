# Documentation dbt — Transformation

Ce dossier contient la documentation opérationnelle du projet dbt (BigQuery sur GCP), structurée comme la documentation infra racine.

## Point d'entrée

- `setup_guide.md` : guide principal et ordre recommandé

## Guides opérationnels

- `gcp_manual_setup.md` : prérequis GCP à faire une fois en amont
- `local_run_commands.md` : exécution dbt avec installation locale
- `docker_run_commands.md` : exécution dbt via Docker Compose
- `dbt_setup.md` : guide rapide (résumé)

## Convention recommandée

- Tout nouveau modèle SQL doit avoir une documentation YAML associée.
- Les tests qualité doivent être versionnés avec les modèles.
- Les changements de configuration dbt (`dbt_project.yml`, `profiles.yml`) doivent être documentés dans ce dossier.
