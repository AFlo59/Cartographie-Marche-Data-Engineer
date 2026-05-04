# IAM — Comptes de service et permissions

Référence complète des comptes de service GCP du projet, de leurs rôles, et de l'état de gestion (Terraform ou manuel).

> **Conventions** :
> - ✅ **Géré par Terraform** — binding appliqué via `terraform apply`
> - 🔧 **Manuel (gcloud)** — commande one-shot à exécuter dans Cloud Shell, non géré par Terraform
> - ❌ **Non fait** — à réaliser
>
> Les commandes ci-dessous utilisent des variables shell. Charger depuis `.env` ou définir manuellement avant d'exécuter :
> ```bash
> GCP_PROJECT_ID="$(gcloud config get project)"
> ```

---

## 1. Comptes de service — création

Les SA ne sont **pas créés par Terraform** dans ce projet (ils sont passés comme variables). Ils doivent être créés une seule fois manuellement.

### 1.1 Ingestion SA

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud iam service-accounts create ingestion-sa \
  --display-name="Ingestion SA" \
  --project=${GCP_PROJECT_ID}
```

**Email** : `ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
**Usage** : exécute les scripts Python d'ingestion dans le Cloud Run Job.
**Statut création** : 🔧 Manuel (one-shot)

---

### 1.2 DBT SA

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud iam service-accounts create dbt-sa \
  --display-name="DBT SA" \
  --project=${GCP_PROJECT_ID}
```

**Email** : `dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
**Usage** : exécute les transformations dbt (BigQuery).
**Statut création** : 🔧 Manuel (one-shot)

---

### 1.3 Dashboard SA

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud iam service-accounts create dashboard-sa \
  --display-name="Dashboard SA" \
  --project=${GCP_PROJECT_ID}
```

**Email** : `dashboard-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
**Usage** : lecture seule des marts pour Looker Studio ou autre outil BI.
**Statut création** : 🔧 Manuel (one-shot)

---

### 1.4 Scheduler SA (optionnel)

Si un compte dédié pour Cloud Scheduler est souhaité (recommandé pour isoler les permissions) :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud iam service-accounts create scheduler-sa \
  --display-name="Scheduler SA" \
  --project=${GCP_PROJECT_ID}
```

**Email** : `scheduler-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
**Usage** : Cloud Scheduler s'en sert pour appeler l'API Cloud Run et déclencher les jobs.
**Note** : si `TF_VAR_scheduler_service_account_email` est vide, `ingestion-sa` est utilisé par défaut via `locals` dans `infra/main.tf`.

---

### 1.5 Terraform Deployer SA (SA WIF)

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud iam service-accounts create terraform-deployer-sa \
  --display-name="Terraform Deployer SA" \
  --project=${GCP_PROJECT_ID}
```

**Email** : `terraform-deployer-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com`
**Usage** : exécute `terraform plan` / `terraform apply` en CI (GitHub Actions via WIF) et en local (ADC).
**Statut création** : 🔧 Manuel (one-shot)

---

## 2. IAM Bindings — `ingestion-sa`

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/storage.objectAdmin` | Bucket | bucket raw | Créer, lire, écraser des objets Parquet dans le bucket raw | ✅ Terraform | `modules/storage` → `google_storage_bucket_iam_member.ingestion_object_admin` |
| `roles/artifactregistry.reader` | Projet | — | Autoriser Cloud Run à tirer l'image d'ingestion depuis Artifact Registry | ✅ Terraform | `modules/compute` → `google_project_iam_member.ingestion_artifact_registry_reader` |
| `roles/bigquery.dataEditor` | Dataset | `raw` | Insérer / écraser des tables dans le dataset raw | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.ingestion_raw_editor` |
| `roles/bigquery.jobUser` | Projet | — | Lancer des jobs BigQuery (INSERT, LOAD, etc.) | ✅ Terraform | `modules/warehouse` → `google_project_iam_member.ingestion_job_user` |
| `roles/secretmanager.secretAccessor` | Secret | `FT_CLIENT_ID`, `FT_CLIENT_SECRET`, `DATAGOUV_API_KEY`, `JOOBLE_API_KEY` | Lire les valeurs des secrets au runtime Cloud Run | ✅ Terraform | `modules/secrets` → `google_secret_manager_secret_iam_member.ingestion_accessor` |

**Commandes gcloud équivalentes** (pour référence ou audit manuel) :

> ⚠️ **Limitation** : `bq add-iam-policy-binding` (dataset-level IAM) retourne `This feature requires allowlisting` et **ne fonctionne pas** sans demande spéciale à GCP. Les bindings dataset BigQuery sont **gérés uniquement via `terraform apply`**.

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
SA="ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
# Le nom du bucket est construit par Terraform : datatalent-<env>-<project_id>-raw
# Récupérer la valeur exacte depuis le terraform output ou depuis .env (INGESTION_RAW_BUCKET)
BUCKET="${INGESTION_RAW_BUCKET}"

# Storage (idempotent)
gcloud storage buckets add-iam-policy-binding gs://${BUCKET} \
  --member="serviceAccount:${SA}" \
  --role="roles/storage.objectAdmin"

# BigQuery jobUser niveau projet (idempotent)
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

# Secret Manager — FT_CLIENT_ID et FT_CLIENT_SECRET
for SECRET in FT_CLIENT_ID FT_CLIENT_SECRET DATAGOUV_API_KEY JOOBLE_API_KEY; do
  gcloud secrets add-iam-policy-binding ${SECRET} \
    --project=${GCP_PROJECT_ID} \
    --member="serviceAccount:${SA}" \
    --role="roles/secretmanager.secretAccessor"
done
```

---

## 3. IAM Bindings — `dbt-sa`

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/bigquery.dataViewer` | Dataset | `raw` | Lire les tables raw (y compris les External Tables) en entrée des modèles dbt | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dbt_raw_viewer` |
| `roles/bigquery.dataEditor` | Dataset | `staging` | Créer / écraser les modèles staging | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dbt_staging_editor` |
| `roles/bigquery.dataEditor` | Dataset | `marts` | Créer / écraser les modèles marts | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dbt_marts_editor` |
| `roles/bigquery.jobUser` | Projet | — | Lancer des jobs BigQuery | ✅ Terraform | `modules/warehouse` → `google_project_iam_member.dbt_job_user` |
| `roles/storage.objectViewer` | Bucket | bucket raw | **Requis pour les BigQuery External Tables** : BQ lit directement GCS au moment de la query | ✅ Terraform | `modules/storage` → `google_storage_bucket_iam_member.dbt_object_viewer` |
| `roles/artifactregistry.reader` | Projet | — | Autoriser Cloud Run à tirer l'image dbt depuis Artifact Registry | ✅ Terraform | `modules/compute` → `google_project_iam_member.dbt_artifact_registry_reader` |

> **Pourquoi `storage.objectViewer` est nécessaire** : les External Tables BigQuery (dataset `raw`) ne stockent pas les données dans BQ — elles lisent les fichiers Parquet dans GCS à chaque requête. BigQuery utilise l'identité du SA dbt pour lire ces objets GCS. Sans ce binding, toute query dbt sur `raw.*` échoue avec `403 Access denied`.

**Commandes gcloud équivalentes** :

> ⚠️ Les bindings dataset (`dataViewer`, `dataEditor`) sont **gérés uniquement via `terraform apply`** (limitation `bq` CLI).

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
SA="dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
BUCKET="${INGESTION_RAW_BUCKET}"

# jobUser niveau projet (idempotent)
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

# Storage objectViewer — requis pour External Tables (idempotent)
gcloud storage buckets add-iam-policy-binding gs://${BUCKET} \
  --member="serviceAccount:${SA}" \
  --role="roles/storage.objectViewer"

# Les bindings dataset (dataViewer raw, dataEditor staging/marts) sont dans Terraform
# → exécuter terraform apply pour les appliquer
```

---

## 4. IAM Bindings — `dashboard-sa`

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/bigquery.dataViewer` | Dataset | `marts` | Lecture seule des données finales pour le dashboard | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dashboard_marts_viewer` |
| `roles/bigquery.jobUser` | Projet | — | Lancer des jobs BigQuery (requêtes dashboard) | ✅ Terraform | `modules/warehouse` → `google_project_iam_member.dashboard_job_user` |

**Commandes gcloud équivalentes** :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
SA="dashboard-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# jobUser niveau projet uniquement via gcloud (idempotent)
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

# Le binding dataset (dataViewer marts) est dans Terraform
# → exécuter terraform apply pour l'appliquer
```

---

## 5. IAM Bindings — SA Scheduler (`scheduler-sa` ou `ingestion-sa` par défaut)

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/run.jobsExecutorWithOverrides` | Job | Cloud Run Job ingestion | Permet à Cloud Scheduler de déclencher le job avec override d'env var | ✅ Terraform | `modules/compute` → `google_cloud_run_v2_job_iam_member.job_invoker` |
| `roles/run.jobsExecutorWithOverrides` | Projet | — | Binding projet pour le déclenchement | ✅ Terraform | `modules/compute` → `google_project_iam_member.job_executor_with_overrides` |

> **Note** : le rôle utilisé est `roles/run.jobsExecutorWithOverrides` (et non `roles/run.invoker`), ce qui permet à Cloud Scheduler d'envoyer un override de variable d'environnement (`INGESTION_SOURCE`) au moment du déclenchement.

**Commande gcloud équivalente** :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
# SA Scheduler — par défaut ingestion-sa si TF_VAR_scheduler_service_account_email est vide
SCHEDULER_SA="ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
JOB_NAME="${TF_VAR_compute_job_name:-datatalent-ingestion-job}"
REGION="${GCP_REGION:-us-central1}"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SCHEDULER_SA}" \
  --role="roles/run.jobsExecutorWithOverrides"
```

---

## 5.1 Cloud Run service agent (pull image Artifact Registry)

Cloud Run utilise le service agent projet :

```
service-<PROJECT_NUMBER>@serverless-robot-prod.iam.gserviceaccount.com
```

Ce compte doit pouvoir lire les images Artifact Registry. Le binding est **géré par Terraform** dans `modules/compute` :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
PROJECT_NUMBER="$(gcloud projects describe ${GCP_PROJECT_ID} --format='value(projectNumber)')"
RUN_SA="service-${PROJECT_NUMBER}@serverless-robot-prod.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${RUN_SA}" \
  --role="roles/artifactregistry.reader"
```

---

## 6. IAM Bindings — SA WIF (`terraform-deployer-sa`)

Ce SA est utilisé par Terraform (CI GitHub Actions via WIF, ou ADC en local). Il a besoin de droits élevés pour gérer les ressources GCP.

| Rôle | Portée | Pourquoi | Statut |
|------|--------|----------|--------|
| `roles/storage.admin` | Projet | Créer / configurer le bucket raw + le bucket tfstate | ✅ Accordé |
| `roles/bigquery.admin` | Projet | Créer / configurer les datasets BigQuery | ✅ Accordé |
| `roles/artifactregistry.admin` | Projet | Créer ET modifier le repo Artifact Registry (cleanup policy, description) | ✅ Accordé |
| `roles/run.admin` | Projet | Déployer les Cloud Run Jobs ingestion + dbt | ✅ Accordé |
| `roles/cloudscheduler.admin` | Projet | Créer / modifier les 5 jobs Cloud Scheduler | ✅ Accordé |
| `roles/secretmanager.admin` | Projet | Créer les secret containers Secret Manager | ✅ Accordé |
| `roles/serviceusage.serviceUsageAdmin` | Projet | Activer les APIs GCP manquantes depuis la CI | ✅ Accordé |
| `roles/iam.serviceAccountUser` | SA Resource | Assigner les SA aux Cloud Run Jobs | ✅ Accordé (via Terraform compute module) |
| `roles/artifactregistry.writer` | Projet | Pousser les images Docker vers Artifact Registry | ✅ Accordé (via Terraform compute module) |
| `roles/logging.configWriter` | Projet | Gérer la rétention du bucket `_Default` Cloud Logging | ✅ Accordé |

**Commandes gcloud** :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
# Remplacer par l'email exact du SA WIF (visible dans GitHub Settings > Secrets: GCP_WIF_SERVICE_ACCOUNT)
TF_SA="terraform-deployer-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Rôles à accorder si manquants (idempotents)
for ROLE in \
  roles/artifactregistry.admin \
  roles/run.admin \
  roles/cloudscheduler.admin \
  roles/secretmanager.admin \
  roles/serviceusage.serviceUsageAdmin; do
  gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
    --member="serviceAccount:${TF_SA}" \
    --role="${ROLE}"
done

# Gère la rétention du bucket _Default Cloud Logging
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/logging.configWriter"

# iam.serviceAccountUser sur ingestion-sa et dbt-sa (géré aussi par Terraform compute module)
INGESTION_SA="ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
DBT_SA="dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts add-iam-policy-binding ${INGESTION_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${GCP_PROJECT_ID}

gcloud iam service-accounts add-iam-policy-binding ${DBT_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${GCP_PROJECT_ID}
```

> **En CI (GitHub Actions WIF)** : le SA utilisé est celui de `GCP_WIF_SERVICE_ACCOUNT`. Les mêmes rôles s'appliquent.

---

## 7. Rôles refusés / non accordés (principe du moindre privilège)

| Compte | Rôle interdit | Raison |
|--------|---------------|--------|
| `ingestion-sa` | `roles/bigquery.dataEditor` sur `staging` / `marts` | L'ingestion n'écrit que dans `raw`. |
| `ingestion-sa` | `roles/storage.admin` | `objectAdmin` sur le bucket suffit. |
| `dbt-sa` | `roles/bigquery.dataEditor` sur `raw` | dbt ne doit qu'écrire dans `staging` et `marts`. |
| `dbt-sa` | `roles/storage.objectAdmin` sur le bucket raw | `objectViewer` suffit pour lire les External Tables. |
| `dashboard-sa` | `roles/bigquery.dataEditor` sur `marts` | Le dashboard n'a besoin que de lire. |
| `dashboard-sa` | Tout accès à `raw` / `staging` | Le dashboard ne doit voir que les données finales de `marts`. |
| `scheduler-sa` | `roles/run.admin` | `run.jobsExecutorWithOverrides` suffit pour déclencher un job existant. |
| Tout SA | `roles/owner` / `roles/editor` | Jamais de rôles primitifs larges sur un compte de service applicatif. |

---

## 8. Récapitulatif — état global

| SA | Création | Permissions core | Statut global |
|----|----------|------------------|---------------|
| `ingestion-sa` | ✅ Créé | Storage objectAdmin ✅ + BQ dataEditor(raw) ✅ + BQ jobUser ✅ + Secret Accessor (FT + DATAGOUV + JOOBLE) ✅ + AR reader ✅ | ✅ Complet |
| `dbt-sa` | ✅ Créé | BQ dataViewer(raw) ✅ + BQ dataEditor(staging,marts) ✅ + BQ jobUser ✅ + Storage objectViewer ✅ + AR reader ✅ | ✅ Complet |
| `dashboard-sa` | ✅ Créé | BQ dataViewer(marts) ✅ + BQ jobUser ✅ | ✅ Complet |
| `scheduler-sa` (ou ingestion-sa) | ✅ Créé | run.jobsExecutorWithOverrides (job + projet) ✅ | ✅ Géré Terraform |
| `terraform-deployer-sa` (SA WIF) | ✅ Créé | storage.admin ✅ + bigquery.admin ✅ + artifactregistry.admin ✅ + run.admin ✅ + cloudscheduler.admin ✅ + secretmanager.admin ✅ + serviceusage.serviceUsageAdmin ✅ + iam.serviceAccountUser ✅ + logging.configWriter ✅ | ✅ Complet |

---

## 9. Notes importantes

### WIF (Workload Identity Federation)

En CI GitHub Actions, le workflow utilise WIF via `google-github-actions/auth@v3` et non une clé JSON. Le SA associé est `terraform-deployer-sa` (ou tout SA lié au WIF pool). Les rôles de la section 6 s'appliquent identiquement.

### Clés JSON

La création de clés JSON est bloquée par la policy org sur ce projet. Le mode recommandé est :
- **Local** : ADC (`gcloud auth application-default login`)
- **CI** : WIF

### `bq add-iam-policy-binding` — limitation connue

La commande `bq add-iam-policy-binding` pour les bindings **au niveau dataset** retourne `This feature requires allowlisting`. **Ne pas utiliser.** Les bindings dataset (`dataEditor`, `dataViewer`) sont gérés exclusivement par Terraform via `google_bigquery_dataset_iam_member`.

### Bindings idempotents via gcloud

Les commandes `add-iam-policy-binding` sont idempotentes — les relancer sur un binding déjà existant ne crée pas de doublon.

### Vérifier les bindings existants

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

# Tous les bindings du projet
gcloud projects get-iam-policy ${GCP_PROJECT_ID} \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)"

# Bindings d'un SA spécifique
SA="ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
gcloud projects get-iam-policy ${GCP_PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA}" \
  --format="table(bindings.role)"
```
