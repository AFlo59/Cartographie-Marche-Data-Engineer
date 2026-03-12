# Orchestration du projet — vue d'ensemble

Ce document décrit l'enchaînement global des composants du projet sans répéter les guides d'exécution détaillés.

## Flux cible

1. Le socle GCP est préparé manuellement.
2. Terraform déploie l'infrastructure.
3. Les secrets runtime sont versionnés dans Secret Manager.
4. Cloud Scheduler déclenche le Cloud Run Job d'ingestion.
5. Les données brutes arrivent dans GCS et BigQuery raw.
6. dbt transforme les données vers `staging` puis `marts`.
7. Le dashboard consomme `marts`.

## Périmètre actuel documenté

La documentation opérationnelle restructurée couvre surtout le périmètre infra actuel :

- provisioning Terraform des ressources GCP,
- IAM nécessaire au fonctionnement des modules infra,
- chargement des secrets runtime,
- release infra via GitHub Actions.

Les étapes dbt et dashboard sont rappelées ici pour la vision cible, mais elles ne sont pas encore documentées comme une release complète dans ces guides infra.

## Guides à suivre selon l'étape

- setup initial : [docs/setup_guide.md](docs/setup_guide.md)
- préparation GCP : [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md)
- exécution Terraform via Docker : [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md)
- exécution Terraform locale : [docs/infra/manual_commands.md](docs/infra/manual_commands.md)
- secrets runtime : [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md)
- CI GitHub ↔ GCP : [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md)
- matrice IAM : [docs/infra/iam_roles.md](docs/infra/iam_roles.md)

## État actuel synthétique

- bucket raw GCS en place,
- datasets BigQuery `raw`, `staging`, `marts` en place,
- modules Terraform Cloud Run Job, Scheduler et Secret Manager câblés,
- workflow CI Terraform via WIF en place,
- rôles IAM principaux préparés,
- secrets runtime présents et versionnés.

Le suivi détaillé des tickets reste dans [docs/infra/infra_epic4_status.md](docs/infra/infra_epic4_status.md).

## Règle documentaire

Ce fichier ne contient volontairement ni longues procédures ni commandes détaillées. Son rôle est uniquement d'expliquer l'ordre global et de rediriger vers le bon guide opérationnel.
