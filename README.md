# Cartographie-Marche-Data-Engineer

Pipeline de données end-to-end : cartographie du marché Data Engineer en France.

## Architecture

```text
APIs sources                GCS (raw)            BigQuery
─────────────               ─────────────────    ────────────────────────────────────
France Travail  ──┐                              raw          (external tables Parquet)
APEC            ──┼──> ingestion Python ──>  bucket  ──>  staging      (tables dbt — 1 par source)
Jooble          ──┤         Cloud Run Job        raw          intermediate (incremental, gold layer)
INSEE Sirene    ──┤                                           marts        (views dashboard)
API Geo         ──┘
```

### Flux d'exécution hebdomadaire (lundi)

| Heure  | Job                      | Description                                        |
| ------ | ------------------------ | -------------------------------------------------- |
| 06h00  | Ingestion France Travail | Cloud Run Job — offres 7 derniers jours            |
| 07h00  | Ingestion APEC           | Cloud Run Job — offres 7 derniers jours            |
| 08h00  | Ingestion Jooble         | Cloud Run Job — offres 7 derniers jours            |
| 09h00  | dbt run + test           | Cloud Run Job — staging → intermediate → marts     |

Ingestions mensuelles (1er du mois) : Sirene 03h00, Geo 04h00.

## Stack technique

| Couche         | Technologie                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| Ingestion      | Python, Cloud Run Job, Cloud Scheduler                                           |
| Stockage raw   | GCS (Parquet, partitions Hive `dt=YYYY-MM-DD`)                                   |
| Entrepôt       | BigQuery — datasets `raw`, `staging`, `intermediate`, `marts`                    |
| Transformation | dbt (BigQuery adapter) — Cloud Run Job                                           |
| IaC            | Terraform — modules `storage`, `warehouse`, `compute`, `scheduler`, `secrets`    |
| CI/CD          | GitHub Actions + Workload Identity Federation                                    |
| Dashboard      | Looker Studio — lecture sur dataset `marts`                                      |

## Modèles dbt

```text
staging/          tables (1 par source, déduplication, nettoyage)
  stg_france_travail__offres
  stg_apec__offres
  stg_jooble__offres
  stg_sirene__etablissements
  stg_geo__communes / departements / regions

intermediate/     incremental merge (unique_key=offre_id, fenêtre -7j)
  int_offres_enrichies   — jointure offres × sirene × geo

marts/            views (exposition dashboard)
  mart_marche_emploi
```

## Structure du repo

```text
src/ingestion/          scripts Python ingestion (France Travail, APEC, Jooble, Sirene, Geo)
dbt/transformation/     projet dbt (models/, macros/, tests/, profiles.yml, Dockerfile)
infra/                  Terraform (main.tf, variables.tf, modules/)
docs/                   documentation plateforme, infra, CI/CD
.github/workflows/      CI GitHub Actions (infra-deploy, dbt-ci, ingestion-ci, python-lint)
docker-compose.yml      services locaux : infra-iac, ingestion-jobs
```

## Démarrage rapide

### Prérequis

- Docker + Docker Compose
- Compte GCP avec projet créé
- Accès GitHub Actions configuré (WIF) — voir [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md)

### Configuration locale

```bash
cp .env.example .env
# Renseigner les valeurs marquées "← À renseigner" dans .env
```

Variables obligatoires dans `.env` :

```ini
GCP_PROJECT_ID=
GOOGLE_CLOUD_PROJECT=
FT_CLIENT_ID=
FT_CLIENT_SECRET=
JOOBLE_API_KEY=
INGESTION_RAW_BUCKET=
TF_VAR_project_id=
TF_VAR_ingestion_service_account_email=
TF_VAR_dbt_service_account_email=
TF_VAR_dashboard_service_account_email=
```

### Déploiement infrastructure

Le déploiement principal passe par GitHub Actions après merge sur `main`.
Pour une exécution locale :

```bash
# Via Docker (recommandé)
docker compose run --rm infra-iac terraform init -backend-config="bucket=<TF_BACKEND_BUCKET>"
docker compose run --rm infra-iac terraform plan
docker compose run --rm infra-iac terraform apply
```

Voir [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md) pour le détail complet.

### Lancer une ingestion localement

```bash
docker compose run --rm -e INGESTION_SOURCE=france_travail ingestion-jobs
```

## Ressources GCP provisionnées

- **GCS** — bucket raw (`datatalent-<env>-<project_id>-raw`) avec lifecycle par source
- **BigQuery** — 4 datasets : `raw`, `staging`, `intermediate`, `marts` + external tables Parquet
- **Cloud Run Jobs** — `datatalent-ingestion-job` + `datatalent-dbt-job`
- **Cloud Scheduler** — 3 jobs (`weekly` + `monthly` + `dbt`)
- **Secret Manager** — `FT_CLIENT_ID`, `FT_CLIENT_SECRET`, `JOOBLE_API_KEY`, `DATAGOUV_API_KEY`
- **Artifact Registry** — repo `datatalent` (`us-central1`) — images ingestion + dbt
- **Comptes de service** — `ingestion-sa`, `dbt-sa`, `dashboard-sa`, `terraform-deployer-sa`

## Documentation

| Document | Contenu |
| --- | --- |
| [docs/setup_guide.md](docs/setup_guide.md) | Point d'entrée — ordre de setup complet |
| [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md) | Setup GCP initial (projets, SA, IAM) |
| [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md) | Création des secrets runtime |
| [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md) | Configuration WIF GitHub ↔ GCP |
| [docs/infra/iam_roles.md](docs/infra/iam_roles.md) | Référence complète des rôles IAM |
| [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md) | Commandes Docker locales |
| [docs/infra/manual_commands.md](docs/infra/manual_commands.md) | Commandes sans Docker |
| [docs/infra/infra_epic4_status.md](docs/infra/infra_epic4_status.md) | Statut tickets INFRA + incidents |

## Statut

- INFRA-01 à 07 : complets
- INFRA-08 (`docs/cost_estimation.md`) : à créer
- INFRA-09 (CI/CD) : partiel — lint Python + dbt parse/compile actifs ; dbt run/test sur main à ajouter
- INFRA-10 (branch protection) : à configurer sur GitHub UI
