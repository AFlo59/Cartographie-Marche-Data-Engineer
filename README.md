# Cartographie-Marche-Data-Engineer

Pipeline de données end-to-end : cartographie du marché Data Engineer en France.

## Architecture

```text
APIs sources                GCS (raw)            BigQuery
─────────────               ─────────────────    ────────────────────────────────────
France Travail  ──┐                              raw          (external tables Parquet)
APEC            ──┼──> ingestion Python ──>  bucket  ──>  staging      (views dbt — 1 par source)
Jooble          ──┤         Cloud Run Job        raw          intermediate (incremental, gold layer)
INSEE Sirene    ──┤                                           marts        (tables dims/faits + views)
API Geo         ──┘
```

### Flux d'exécution (Cloud Scheduler)

Chaque scheduler déclenche **une seule** exécution du Cloud Run Job ; les sources d'un
groupe sont enchaînées **en série** dans cette exécution (cf. `src/ingestion/main.py`).

| Scheduler                      | Cron (Europe/Paris) | Job déclenché        | Sources (en série)                       |
| ------------------------------ | ------------------- | -------------------- | ---------------------------------------- |
| `datatalent-ingestion-weekly`  | `0 6 * * 1` (lun. 6h) | ingestion (`weekly`)  | france_travail → apec → jooble           |
| `datatalent-ingestion-monthly` | `0 3 1 * *` (1er 3h)  | ingestion (`monthly`) | sirene → geo                             |
| `datatalent-dbt`               | `0 9 * * 1` (lun. 9h) | dbt                   | dbt run + test (staging → intermediate → marts) |

## Stack technique

| Couche         | Technologie                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| Ingestion      | Python, Cloud Run Job, Cloud Scheduler                                           |
| Stockage raw   | GCS (Parquet, partitions Hive `dt=YYYY-MM-DD`)                                   |
| Entrepôt       | BigQuery — datasets `raw`, `staging`, `intermediate`, `marts`                    |
| Transformation | dbt (BigQuery adapter) — Cloud Run Job                                           |
| IaC            | Terraform — modules `storage`, `warehouse`, `compute`, `scheduler`, `secrets`, `monitoring` |
| CI/CD          | GitHub Actions + Workload Identity Federation                                    |
| Monitoring     | Cloud Monitoring (opt-in) — alert policies échec Cloud Run Job + canaux email    |
| Coûts          | Billing export BigQuery (opt-in) → marts de coûts dbt                            |
| Dashboard      | *Externe* — Looker Studio d'un collègue, lecture seule sur `marts` (non provisionné ici) |

## Modèles dbt

Projet `datatalent_transformation`. UDFs BigQuery créées au `on-run-start`
(`parse_event_ts`, `parse_contrat`, `parse_salaire_auto`, `lambert93_to_latlon`).

```text
staging/          views (1 par source, nettoyage + typage)
  stg_france_travail__offres
  stg_apec__offres
  stg_jooble__offres
  stg_sirene__etablissements / unites_legales
  stg_geo__communes / departements / regions

intermediate/     incremental merge — gold layer (jointure géo + Sirene)
  int_france_travail__enrichie   (unique_key=offre_id)
  int_apec__enrichie             (unique_key=offre_id)
  int_jooble__enrichie           (unique_key=offre_id)
  int_sirene__entreprises        (unique_key=siret, référentiel consolidé)

marts/            tables (dims/faits) + views (exposition dashboard)
  fct_offres            — faits unifiés (UNION France Travail + APEC + Jooble)
  dim_date              — calendrier
  dim_territoire        — géographie (commune/dept/région)
  dim_entreprise        — référentiel Sirene exposé BI
  dim_source_offre      — dimension statique des 3 sources d'offres
  mart_marche_emploi    — vue BI principale (offres enrichies)
  mart_couts__mensuel / __annuel               — coûts GCP (source billing export)
  mart_couts_ressource__mensuel / __annuel     — coûts GCP par ressource
```

Les marts de coûts (`mart_couts*`) lisent l'export billing BigQuery et retournent un
schéma vide tant que l'export n'est pas activé. Le dataset `billing_export` est **créé
manuellement dans GCP** (Billing → Export BigQuery), hors Terraform/CI ; Terraform
ajoute seulement le binding IAM `dbt-sa` → `dataViewer` (opt-in) — voir
[docs/infra/billing_cost_setup.md](docs/infra/billing_cost_setup.md).

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

- **GCS** — bucket raw (`datatalent-<env>-<project_id>-raw`) avec lifecycle de purge par source (30/31 j)
- **BigQuery** — 4 datasets : `raw`, `staging`, `intermediate`, `marts` + 8 external tables Parquet
- **Cloud Run Jobs** — `datatalent-ingestion-job` + `datatalent-dbt-job`
- **Cloud Scheduler** — 3 jobs (`weekly` + `monthly` + `dbt`)
- **Secret Manager** — `FT_CLIENT_ID`, `FT_CLIENT_SECRET`, `JOOBLE_API_KEY`, `DATAGOUV_API_KEY`
- **Artifact Registry** — repo `datatalent` (`us-central1`) — images ingestion + dbt
- **Cloud Monitoring** *(opt-in `create_monitoring`)* — alert policies échec Cloud Run Job + canaux email
- **Comptes de service** — `ingestion-sa`, `dbt-sa`, `dashboard-sa`, `terraform-deployer-sa`

Inventaire détaillé (config exacte, IAM, ressources conditionnelles) :
[docs/infra/resource_inventory.md](docs/infra/resource_inventory.md).

> Le dashboard **n'est pas une ressource de ce projet** : aucun serveur BI n'est
> hébergé. La restitution se fait via le Looker Studio d'un collègue, qui exploite
> le dataset `marts` en **lecture seule** (`dashboard-sa` a `roles/bigquery.dataViewer`
> sur `marts`).

## Documentation

| Document | Contenu |
| --- | --- |
| [docs/setup_guide.md](docs/setup_guide.md) | Point d'entrée — ordre de setup complet |
| [docs/architecture.md](docs/architecture.md) | Schéma d'architecture global (Mermaid) |
| [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md) | Setup GCP initial (projets, SA, IAM) |
| [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md) | Création des secrets runtime |
| [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md) | Configuration WIF GitHub ↔ GCP |
| [docs/cicd/deployment_orchestration.md](docs/cicd/deployment_orchestration.md) | Orchestration globale + pipeline CI/CD |
| [docs/infra/resource_inventory.md](docs/infra/resource_inventory.md) | Inventaire exhaustif des ressources GCP |
| [docs/infra/infrastructure_flow.md](docs/infra/infrastructure_flow.md) | Flux infra & déploiement Terraform |
| [docs/infra/iam_roles.md](docs/infra/iam_roles.md) | Référence complète des rôles IAM |
| [docs/infra/monitoring_setup.md](docs/infra/monitoring_setup.md) | Alerting Cloud Monitoring (opt-in) |
| [docs/infra/billing_cost_setup.md](docs/infra/billing_cost_setup.md) | Export billing BigQuery + marts de coûts |
| [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md) | Commandes Terraform via Docker |
| [docs/infra/manual_commands.md](docs/infra/manual_commands.md) | Commandes Terraform sans Docker |
| [docs/infra/infra_epic4_status.md](docs/infra/infra_epic4_status.md) | Statut tickets INFRA + incidents |
| [docs/ingestion/ingestion_docker.md](docs/ingestion/ingestion_docker.md) | Exécution de l'ingestion via Docker |
| [docs/dbt/setup_guide.md](docs/dbt/setup_guide.md) | Setup et exécution dbt (local + Docker) |
