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

## Décision d'architecture ingestion (recommandée)

### Choix retenu

- **Un seul Cloud Run Job** d'ingestion (`datatalent-ingestion-job`),
- **3 jobs Cloud Scheduler** (france_travail, sirene, geo),
- chaque scheduler envoie un override de variable d'environnement `INGESTION_SOURCE`.

Ce choix est le plus optimisé actuellement pour votre projet (coût + simplicité opérationnelle).

### Pourquoi c'est le plus efficace aujourd'hui

- une seule image Docker à builder/pusher,
- un seul job Cloud Run à maintenir,
- moins de surface IAM/Terraform,
- coût d'exploitation global souvent plus faible (fréquence faible: hebdo + mensuel).

### Est-ce qu'on "overwrite" les données d'ingestion ?

Recommandation:

- **ne pas écraser le même objet** à chaque run,
- écrire par **source + période d'exécution** (ex: `raw/<source>/YYYY/MM/` ou `raw/<source>/run_date=YYYY-MM-DD/`),
- garder un pointeur "latest" si besoin (facultatif), mais conserver l'historique brut.

Avec cette stratégie, un seul job reste propre et traçable sans collision entre sources.

### Quand passer à 3 Cloud Run Jobs distincts

Basculer vers 3 jobs uniquement si:

- CPU/RAM/timeout très différents par source,
- cadence très différente (ex: une source quotidienne lourde),
- besoin d'isolation forte des incidents/SLA.

Sinon, garder **1 job paramétré** est la meilleure option.

## Note coût (ordre de grandeur)

- À faible volumétrie, la différence de coût pur entre 1 job paramétré et 3 jobs séparés est généralement faible.
- Le vrai gain vient surtout de:
	- limiter CPU/RAM au strict besoin,
	- réduire la durée d'exécution,
	- éviter les re-téléchargements complets inutiles,
	- gérer l'incrémental quand l'API le permet.

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
