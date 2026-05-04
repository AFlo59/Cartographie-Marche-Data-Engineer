# Inventaire des ressources GCP — configuration complète

Ce document centralise toutes les ressources GCP créées par Terraform, leur configuration précise, et les paramètres CI/CD associés. Source de vérité : les fichiers Terraform et le workflow `infra-deploy.yml`.

---

## Sommaire

1. [Cloud Storage — Bucket raw](#1-cloud-storage--bucket-raw)
2. [Cloud Storage — Bucket tfstate](#2-cloud-storage--bucket-tfstate)
3. [BigQuery — Datasets](#3-bigquery--datasets)
4. [BigQuery — External Tables](#4-bigquery--external-tables)
5. [Artifact Registry](#5-artifact-registry)
6. [Cloud Run Job — Ingestion](#6-cloud-run-job--ingestion)
7. [Cloud Run Job — dbt](#7-cloud-run-job--dbt)
8. [Secret Manager](#8-secret-manager)
9. [Cloud Scheduler](#9-cloud-scheduler)
10. [Cloud Logging](#10-cloud-logging)
11. [IAM Bindings](#11-iam-bindings)
12. [Ressources conditionnelles — récapitulatif](#12-ressources-conditionnelles--récapitulatif)

---

## 1. Cloud Storage — Bucket raw

**Ressource Terraform** : `module.storage.google_storage_bucket.raw`  
**Fichier** : [infra/modules/storage/main.tf](../../infra/modules/storage/main.tf)

| Paramètre | Valeur |
| --- | --- |
| Nom | `datatalent-dev-<project_id>-raw` (calculé) |
| Région | `europe-west1` — **single-region** |
| Uniform bucket-level access | `true` |
| Public access prevention | `enforced` |
| Force destroy | `false` |
| Versioning | activé |

### Règles lifecycle (7 règles actives en CI)

| Règle | Condition | Action |
| --- | --- | --- |
| Transition NEARLINE | `age ≥ 30j` (tous objets) | `SetStorageClass = NEARLINE` |
| Purge `raw/france_travail/` | `age ≥ 60j` | Delete |
| Purge `raw/apec/` | `age ≥ 60j` | Delete |
| Purge `raw/jooble/` | `age ≥ 60j` | Delete |
| Purge `raw/sirene/` | `age ≥ 60j` | Delete |
| Purge `raw/geo/` | `age ≥ 60j` | Delete |
| Suppression globale | `age ≥ 365j` | Delete |
| Nettoyage versions ARCHIVED | `num_newer_versions ≥ 2` | Delete |

La règle ARCHIVED s'applique uniquement aux objets réécrits (sirene, geo) — sans effet sur france_travail/apec/jooble qui écrivent toujours vers un nouveau chemin.

### IAM bucket

| Service Account | Rôle |
| --- | --- |
| `ingestion-sa` | `roles/storage.objectAdmin` |
| `dbt-sa` | `roles/storage.objectViewer` (requis pour les External Tables) |

---

## 2. Cloud Storage — Bucket tfstate

**Non géré par Terraform** — créé par le step `Ensure Terraform backend bucket exists` dans `infra-deploy.yml` (push `main` uniquement).

| Paramètre | Valeur |
| --- | --- |
| Nom | `datatalent-tfstate-<project_id>` (hardcodé dans le workflow) |
| Région | `europe-west1` |
| Versioning | activé |
| Lifecycle | Supprimer versions ARCHIVED quand `numNewerVersions ≥ 2` (conserve live + 1 précédente) |
| Accès | Uniform bucket-level access |

Backend Terraform initialisé dynamiquement :

```bash
terraform init -backend-config="bucket=datatalent-tfstate-<project_id>"
```

---

## 3. BigQuery — Datasets

**Ressource Terraform** : `module.warehouse.google_bigquery_dataset.*`  
**Fichier** : [infra/modules/warehouse/main.tf](../../infra/modules/warehouse/main.tf)  
**Location** : `EU` — **multi-région Europe** (différent du bucket GCS qui est single-region)

| Dataset | ID |
| --- | --- |
| raw | `raw` |
| staging | `staging` |
| intermediate | `intermediate` |
| marts | `marts` |

### IAM datasets

| Service Account | Dataset | Rôle |
| --- | --- | --- |
| `ingestion-sa` | `raw` | `roles/bigquery.dataEditor` |
| `dbt-sa` | `raw` | `roles/bigquery.dataViewer` |
| `dbt-sa` | `staging` | `roles/bigquery.dataEditor` |
| `dbt-sa` | `intermediate` | `roles/bigquery.dataEditor` |
| `dbt-sa` | `marts` | `roles/bigquery.dataEditor` |
| `dashboard-sa` | `marts` | `roles/bigquery.dataViewer` |

### IAM projet — `roles/bigquery.jobUser`

Conditionnel : `manage_project_job_user_bindings = true` (local) / `false` en CI.

> En CI (`manage_project_job_user_bindings = false`), ces bindings projet ne sont **pas** gérés par Terraform — ils doivent avoir été appliqués manuellement. Voir [docs/infra/iam_roles.md](iam_roles.md) section 4.

---

## 4. BigQuery — External Tables

**Ressource Terraform** : `module.warehouse.google_bigquery_table.*`  
**Conditionnel** : `create_external_tables = true`  
**Format** : PARQUET — `autodetect = true` — `deletion_protection = false`  
**Location** : héritée du dataset `raw` → `EU`

| Table BQ | URI GCS source | Partitionnement |
| --- | --- | --- |
| `raw.france_travail_offres` | `raw/france_travail/dt=*/offres.parquet` | Hive AUTO (colonne `dt`) |
| `raw.apec_offres` | `raw/apec/dt=*/offres.parquet` | Hive AUTO (colonne `dt`) |
| `raw.jooble_offres` | `raw/jooble/dt=*/offres.parquet` | Hive AUTO (colonne `dt`) |
| `raw.sirene_etablissements` | `raw/sirene/*/StockEtablissement.parquet` | Aucun (wildcard mensuel) |
| `raw.sirene_unites_legales` | `raw/sirene/*/StockUniteLegale.parquet` | Aucun (wildcard mensuel) |
| `raw.geo_communes` | `raw/geo/*/communes.parquet` | Aucun (wildcard mensuel) |
| `raw.geo_departements` | `raw/geo/*/departements.parquet` | Aucun (wildcard mensuel) |
| `raw.geo_regions` | `raw/geo/*/regions.parquet` | Aucun (wildcard mensuel) |

`require_partition_filter = false` sur les 3 tables Hive-partitionnées.  
Zéro stockage BigQuery facturé : BQ lit directement GCS à la query.

---

## 5. Artifact Registry

**Ressource Terraform** : `module.compute.google_artifact_registry_repository.datatalent`  
**Fichier** : [infra/modules/compute/main.tf](../../infra/modules/compute/main.tf)

| Paramètre | Valeur |
| --- | --- |
| Nom du repo | `datatalent` |
| Région | `europe-west1` — **single-region** |
| Format | `DOCKER` |
| Dry run cleanup | `false` |

### Cleanup policies

| Policy | Action | Condition |
| --- | --- | --- |
| `keep-recent-versions` | KEEP | `most_recent_versions = 2` (latest + 1 précédente) |
| `delete-older-versions` | DELETE | `tag_state = ANY`, `older_than = 1s` (purge quasi-immédiate, asynchrone GCP) |

### Images gérées

- `ingestion:latest` + `ingestion:<sha8>`
- `dbt:latest` + `dbt:<sha8>`

### IAM Artifact Registry

| Service Account | Rôle | Niveau |
| --- | --- | --- |
| `terraform-deployer-sa` (CI) | `roles/artifactregistry.writer` | projet |
| `terraform-deployer-sa` (CI) | `roles/iam.serviceAccountUser` | projet |
| `ingestion-sa` | `roles/artifactregistry.reader` | projet |
| `dbt-sa` | `roles/artifactregistry.reader` | projet |
| `service-<NUM>@serverless-robot-prod` | `roles/artifactregistry.reader` | projet |

---

## 6. Cloud Run Job — Ingestion

**Ressource Terraform** : `module.compute.google_cloud_run_v2_job.ingestion[0]`  
**Conditionnel** : `create_compute_job = true`

| Paramètre | Valeur |
| --- | --- |
| Nom | `datatalent-ingestion-job` |
| Région | `europe-west1` |
| Image | `europe-west1-docker.pkg.dev/<project_id>/datatalent/ingestion:latest` |
| CPU | `1` |
| Mémoire | `512Mi` |
| Timeout | `1800s` (30 min) |
| Max retries | `1` |
| Service account | `ingestion-sa@<project_id>.iam.gserviceaccount.com` |

### Variables d'environnement — plain

| Variable | Valeur injectée par Terraform |
| --- | --- |
| `GCP_PROJECT_ID` | `<project_id>` |
| `INGESTION_RAW_BUCKET` | `datatalent-dev-<project_id>-raw` |
| `INGESTION_FRANCE_TRAVAIL_PREFIX` | `raw/france_travail/` |
| `INGESTION_SIRENE_PREFIX` | `raw/sirene/` |
| `INGESTION_GEO_PREFIX` | `raw/geo/` |
| `INGESTION_APEC_PREFIX` | `raw/apec/` |
| `INGESTION_JOOBLE_PREFIX` | `raw/jooble/` |

### Variables d'environnement — depuis Secret Manager (`version = latest`)

| Variable | Secret Manager ID |
| --- | --- |
| `FT_CLIENT_ID` | `FT_CLIENT_ID` |
| `FT_CLIENT_SECRET` | `FT_CLIENT_SECRET` |
| `JOOBLE_API_KEY` | `JOOBLE_API_KEY` |
| `DATAGOUV_API_KEY` | `DATAGOUV_API_KEY` |

---

## 7. Cloud Run Job — dbt

**Ressource Terraform** : `module.compute.google_cloud_run_v2_job.dbt[0]`  
**Conditionnel** : `create_dbt_job = true`

| Paramètre | Valeur |
| --- | --- |
| Nom | `datatalent-dbt-job` |
| Région | `europe-west1` |
| Image | `europe-west1-docker.pkg.dev/<project_id>/datatalent/dbt:latest` |
| CPU | `1` |
| Mémoire | `1Gi` |
| Timeout | `1800s` (30 min) |
| Max retries | `0` (pas de retry — idempotence non garantie) |
| Service account | `dbt-sa@<project_id>.iam.gserviceaccount.com` |

### Variables d'environnement — plain

| Variable | Valeur |
| --- | --- |
| `GCP_PROJECT_ID` | `<project_id>` |
| `DBT_TARGET` | `dev` |

---

## 8. Secret Manager

**Ressource Terraform** : `module.secrets.google_secret_manager_secret.secrets`  
**Fichier** : [infra/modules/secrets/main.tf](../../infra/modules/secrets/main.tf)  
**Replication** : `auto {}` — **multi-région géré automatiquement par Google**

| Secret ID | Usage | Valeur gérée par Terraform |
| --- | --- | --- |
| `FT_CLIENT_ID` | OAuth2 France Travail — client ID | Conteneur créé, valeur à alimenter manuellement |
| `FT_CLIENT_SECRET` | OAuth2 France Travail — client secret | Idem |
| `JOOBLE_API_KEY` | API key Jooble | Idem |
| `DATAGOUV_API_KEY` | API key data.gouv.fr | Idem |

**IAM** : `ingestion-sa` → `roles/secretmanager.secretAccessor` sur chacun des 4 secrets.

Alimentation des valeurs : voir [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)

---

## 9. Cloud Scheduler

**Ressource Terraform** : `module.scheduler[0].google_cloud_scheduler_job.ingestion`  
**Fichier** : [infra/modules/scheduler/main.tf](../../infra/modules/scheduler/main.tf)  
**Conditionnel** : `create_compute_job = true`

| Paramètre global | Valeur |
| --- | --- |
| Région | `europe-west1` |
| Timezone | `Europe/Paris` |
| attempt_deadline | `320s` |
| retry_count | `3` |
| Méthode HTTP | POST |
| Target | `https://run.googleapis.com/v2/projects/<project>/locations/europe-west1/jobs/datatalent-ingestion-job:run` |
| Auth | OAuth2 — `ingestion-sa` — scope `cloud-platform` |
| Body | JSON : `containerOverrides.env[INGESTION_SOURCE=<source>]` |

### 5 jobs actifs

| Nom | Schedule | Fréquence |
| --- | --- | --- |
| `datatalent-ingestion-france_travail` | `0 6 * * 1` | Hebdomadaire — lundi 6h |
| `datatalent-ingestion-apec` | `0 7 * * 1` | Hebdomadaire — lundi 7h |
| `datatalent-ingestion-jooble` | `0 8 * * 1` | Hebdomadaire — lundi 8h |
| `datatalent-ingestion-sirene` | `0 3 1 * *` | Mensuel — 1er du mois 3h |
| `datatalent-ingestion-geo` | `0 4 1 * *` | Mensuel — 1er du mois 4h |

---

## 10. Cloud Logging

**Ressource Terraform** : `module.compute.google_logging_project_bucket_config.default_retention[0]`  
**Conditionnel** : `manage_log_retention = true`

| Paramètre | Valeur |
| --- | --- |
| Location | `global` |
| Bucket ID | `_Default` |
| Rétention | `60j` |

> Nécessite `roles/logging.configWriter` sur le SA Terraform. Ce rôle est manquant sur `terraform-deployer-sa` — cause erreur 403 lors du `terraform apply`. Voir [docs/infra/iam_roles.md](iam_roles.md) section 6.

---

## 11. IAM Bindings

### Géré par Terraform — récapitulatif complet

**Module `compute`**

| Member | Ressource | Rôle |
| --- | --- | --- |
| `terraform-deployer-sa` | projet | `roles/artifactregistry.writer` |
| `terraform-deployer-sa` | projet | `roles/iam.serviceAccountUser` |
| `ingestion-sa` | projet | `roles/artifactregistry.reader` |
| `dbt-sa` | projet | `roles/artifactregistry.reader` |
| Cloud Run service agent | projet | `roles/artifactregistry.reader` |
| `ingestion-sa` (scheduler-sa) | job ingestion | `roles/run.jobsExecutorWithOverrides` |
| `ingestion-sa` (scheduler-sa) | projet | `roles/run.jobsExecutorWithOverrides` |

**Module `storage`**

| Member | Ressource | Rôle |
| --- | --- | --- |
| `ingestion-sa` | bucket raw | `roles/storage.objectAdmin` |
| `dbt-sa` | bucket raw | `roles/storage.objectViewer` |

**Module `warehouse`**

| Member | Dataset | Rôle |
| --- | --- | --- |
| `ingestion-sa` | `raw` | `roles/bigquery.dataEditor` |
| `dbt-sa` | `raw` | `roles/bigquery.dataViewer` |
| `dbt-sa` | `staging` | `roles/bigquery.dataEditor` |
| `dbt-sa` | `intermediate` | `roles/bigquery.dataEditor` |
| `dbt-sa` | `marts` | `roles/bigquery.dataEditor` |
| `dashboard-sa` | `marts` | `roles/bigquery.dataViewer` |
| `ingestion-sa` | projet | `roles/bigquery.jobUser` (si `manage_project_job_user_bindings=true`) |
| `dbt-sa` | projet | `roles/bigquery.jobUser` (si `manage_project_job_user_bindings=true`) |
| `dashboard-sa` | projet | `roles/bigquery.jobUser` (si `manage_project_job_user_bindings=true`) |

**Module `secrets`**

| Member | Secret | Rôle |
| --- | --- | --- |
| `ingestion-sa` | `FT_CLIENT_ID` | `roles/secretmanager.secretAccessor` |
| `ingestion-sa` | `FT_CLIENT_SECRET` | `roles/secretmanager.secretAccessor` |
| `ingestion-sa` | `JOOBLE_API_KEY` | `roles/secretmanager.secretAccessor` |
| `ingestion-sa` | `DATAGOUV_API_KEY` | `roles/secretmanager.secretAccessor` |

### Non géré par Terraform — à appliquer manuellement

| Member | Rôle | Raison |
| --- | --- | --- |
| `terraform-deployer-sa` | `roles/storage.admin` | Terraform IaC |
| `terraform-deployer-sa` | `roles/bigquery.admin` | Terraform IaC |
| `terraform-deployer-sa` | `roles/artifactregistry.admin` | Terraform IaC |
| `terraform-deployer-sa` | `roles/run.admin` | Terraform IaC |
| `terraform-deployer-sa` | `roles/cloudscheduler.admin` | Terraform IaC |
| `terraform-deployer-sa` | `roles/secretmanager.admin` | Terraform IaC |
| `terraform-deployer-sa` | `roles/serviceusage.serviceUsageAdmin` | Activation APIs en CI |
| `terraform-deployer-sa` | `roles/logging.configWriter` | **MANQUANT** — erreur 403 Cloud Logging |

---

## 12. Ressources conditionnelles — récapitulatif

| Ressource | Flag | Valeur en CI | Valeur locale (.env.example) |
| --- | --- | --- | --- |
| Cloud Run Job ingestion | `create_compute_job` | `true` | `false` |
| Cloud Run Job dbt | `create_dbt_job` | `true` | `false` |
| Cloud Scheduler (5 jobs) | `create_compute_job` | `true` | `false` |
| External Tables BQ (8) | `create_external_tables` | `true` | `false` |
| Cloud Logging retention | `manage_log_retention` | `true` | `true` |
| BigQuery jobUser bindings projet | `manage_project_job_user_bindings` | `false` | `true` |

---

## Localisation des fichiers sources

| Fichier | Rôle |
| --- | --- |
| [infra/variables.tf](../../infra/variables.tf) | Déclaration et valeurs par défaut de toutes les variables |
| [infra/main.tf](../../infra/main.tf) | Wiring des modules, locals, checks |
| [infra/versions.tf](../../infra/versions.tf) | Provider `google ~> 5.0`, `time ~> 0.9`, Terraform `>= 1.6.0`, backend GCS |
| [infra/modules/storage/main.tf](../../infra/modules/storage/main.tf) | Bucket raw + lifecycle + IAM bucket |
| [infra/modules/warehouse/main.tf](../../infra/modules/warehouse/main.tf) | Datasets BQ + External Tables + IAM datasets |
| [infra/modules/compute/main.tf](../../infra/modules/compute/main.tf) | AR repo + Cloud Run Jobs + time_sleep 90s + IAM AR + Cloud Logging |
| [infra/modules/scheduler/main.tf](../../infra/modules/scheduler/main.tf) | 5 Cloud Scheduler jobs |
| [infra/modules/secrets/main.tf](../../infra/modules/secrets/main.tf) | Secret Manager containers + IAM secretAccessor |
| [.github/workflows/infra-deploy.yml](../../.github/workflows/infra-deploy.yml) | CI/CD : valeurs actives en production |
| [infra/terraform.tfvars.example](../../infra/terraform.tfvars.example) | Template vars locales |
| [.env.example](../../.env.example) | Template variables d'environnement (ingestion + Terraform + dbt) |

---

**Dernière mise à jour** : Mai 2026
