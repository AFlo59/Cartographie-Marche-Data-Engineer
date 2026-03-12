# IAM — Comptes de service et permissions

Référence complète des comptes de service GCP du projet, de leurs rôles, et de l'état de gestion (Terraform ou manuel).

> **Projet GCP** : `cartographie-data-engineer`
> **Conventions** :
> - ✅ **Géré par Terraform** — binding appliqué via `terraform apply`
> - 🔧 **Manuel (gcloud)** — commande one-shot à exécuter dans Cloud Shell, non géré par Terraform
> - ❌ **Non fait** — à réaliser

---

## 1. Comptes de service — création

Les SA ne sont **pas créés par Terraform** dans ce projet (ils sont passés comme variables). Ils doivent être créés une seule fois manuellement.

### 1.1 Ingestion SA

```bash
gcloud iam service-accounts create ingestion-sa \
  --display-name="Ingestion SA" \
  --project=cartographie-data-engineer
```

**Email** : `ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com`
**Usage** : exécute les scripts Python d'ingestion dans le Cloud Run Job.
**Statut création** : 🔧 Manuel (one-shot)

---

### 1.2 DBT SA

```bash
gcloud iam service-accounts create dbt-sa \
  --display-name="DBT SA" \
  --project=cartographie-data-engineer
```

**Email** : `dbt-sa@cartographie-data-engineer.iam.gserviceaccount.com`
**Usage** : exécute les transformations dbt (BigQuery).
**Statut création** : 🔧 Manuel (one-shot)

---

### 1.3 Dashboard SA

```bash
gcloud iam service-accounts create dashboard-sa \
  --display-name="Dashboard SA" \
  --project=cartographie-data-engineer
```

**Email** : `dashboard-sa@cartographie-data-engineer.iam.gserviceaccount.com`
**Usage** : lecture seule des marts pour Looker Studio ou autre outil BI.
**Statut création** : 🔧 Manuel (one-shot)

---

### 1.4 Scheduler SA (optionnel)

Si on souhaite un compte dédié pour Cloud Scheduler (recommandé pour isoler les permissions) :

```bash
gcloud iam service-accounts create scheduler-sa \
  --display-name="Scheduler SA" \
  --project=cartographie-data-engineer
```

**Email** : `scheduler-sa@cartographie-data-engineer.iam.gserviceaccount.com`
**Usage** : Cloud Scheduler s'en sert pour appeler l'API Cloud Run et déclencher les jobs.
**Statut création** : 🔧 Manuel (optionnel — si non défini, `ingestion-sa` est utilisé par défaut via `locals` dans `infra/main.tf`)

---

### 1.5 Terraform Deployer SA

```bash
gcloud iam service-accounts create terraform-deployer-sa \
  --display-name="Terraform Deployer SA" \
  --project=cartographie-data-engineer
```

**Email** : `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com`
**Usage** : exécute `terraform plan` / `terraform apply` en CI (GitHub Actions via WIF) et en local (ADC ou clé JSON si autorisée).
**Statut création** : 🔧 Manuel (one-shot)

---

## 2. IAM Bindings — `ingestion-sa`

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/storage.objectAdmin` | Bucket | `datatalent-dev-cartographie-data-engineer-raw` | Créer, lire, écraser des objets Parquet dans le bucket raw | ✅ Terraform + ✅ Manuel appliqué | `modules/storage` → `google_storage_bucket_iam_member.ingestion_object_admin` |
| `roles/bigquery.dataEditor` | Dataset | `raw` | Insérer / écraser des tables dans le dataset raw | ✅ Terraform (appliqué INFRA-03) | `modules/warehouse` → `google_bigquery_dataset_iam_member.ingestion_raw_editor` |
| `roles/bigquery.jobUser` | Projet | — | Lancer des jobs BigQuery (INSERT, LOAD, etc.) | ✅ Terraform + ✅ Manuel appliqué | `modules/warehouse` → `google_project_iam_member.ingestion_job_user` |
| `roles/secretmanager.secretAccessor` | Secret | `FT_CLIENT_ID`, `FT_CLIENT_SECRET` | Lire les valeurs des secrets au runtime Cloud Run | ✅ Manuel appliqué (terraform apply INFRA-06 confirmera) | `modules/secrets` → `google_secret_manager_secret_iam_member.ingestion_accessor` |
| `roles/secretmanager.secretAccessor` | Secret | `DATAGOUV_API_KEY` | Lire la clé API data.gouv au runtime | ❌ Secret inexistant → créer + binding (voir fix ci-dessous) | `modules/secrets` → `google_secret_manager_secret_iam_member.ingestion_accessor` |

**Commandes gcloud équivalentes** (pour référence ou audit manuel) :

> ⚠️ **Limitation** : `bq add-iam-policy-binding` (dataset-level IAM) retourne `This feature requires allowlisting` et **ne fonctionne pas** sans demande spéciale à GCP. Les bindings dataset BigQuery sont **gérés uniquement via `terraform apply`** (déjà appliqués lors de INFRA-03).

```bash
SA="ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"
BUCKET="datatalent-dev-cartographie-data-engineer-raw"

# Storage (idempotent)
gcloud storage buckets add-iam-policy-binding gs://${BUCKET} \
  --member="serviceAccount:${SA}" \
  --role="roles/storage.objectAdmin"

# BigQuery jobUser niveau projet (idempotent)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

# Secret Manager — FT_CLIENT_ID et FT_CLIENT_SECRET (secrets déjà existants)
for SECRET in FT_CLIENT_ID FT_CLIENT_SECRET; do
  gcloud secrets add-iam-policy-binding ${SECRET} \
    --project=${PROJECT} \
    --member="serviceAccount:${SA}" \
    --role="roles/secretmanager.secretAccessor"
done

# Secret Manager — DATAGOUV_API_KEY : créer le secret d'abord, puis le binding
gcloud secrets create DATAGOUV_API_KEY \
  --project=${PROJECT} \
  --replication-policy=automatic

gcloud secrets add-iam-policy-binding DATAGOUV_API_KEY \
  --project=${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/secretmanager.secretAccessor"
```

---

## 3. IAM Bindings — `dbt-sa`

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/bigquery.dataViewer` | Dataset | `raw` | Lire les tables raw en entrée des modèles dbt | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dbt_raw_viewer` |
| `roles/bigquery.dataEditor` | Dataset | `staging` | Créer / écraser les modèles staging | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dbt_staging_editor` |
| `roles/bigquery.dataEditor` | Dataset | `marts` | Créer / écraser les modèles marts | ✅ Terraform | `modules/warehouse` → `google_bigquery_dataset_iam_member.dbt_marts_editor` |
| `roles/bigquery.jobUser` | Projet | — | Lancer des jobs BigQuery | ✅ Terraform | `modules/warehouse` → `google_project_iam_member.dbt_job_user` |

**Commandes gcloud équivalentes** :

> ⚠️ **Limitation** : les bindings dataset BigQuery (`dataViewer`, `dataEditor`) ne peuvent pas être appliqués via `bq` CLI (erreur `allowlisting`). Ils sont **gérés uniquement via `terraform apply`** (déjà appliqués lors de INFRA-03).

```bash
SA="dbt-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"

# jobUser niveau projet uniquement via gcloud (idempotent)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

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

> ⚠️ **Limitation** : le binding dataset (`dataViewer` sur `marts`) ne peut pas être appliqué via `bq` CLI. Il est **géré uniquement via `terraform apply`** (déjà appliqué lors de INFRA-03).

```bash
SA="dashboard-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"

# jobUser niveau projet uniquement via gcloud (idempotent)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

# Le binding dataset (dataViewer marts) est dans Terraform
# → exécuter terraform apply pour l'appliquer
```

---

## 5. IAM Bindings — `scheduler-sa` (ou `ingestion-sa` par défaut)

| Rôle | Portée | Ressource cible | Pourquoi | Statut | Ressource Terraform |
|------|--------|-----------------|----------|--------|---------------------|
| `roles/run.invoker` | Projet | — | Permet à Cloud Scheduler d'appeler l'API Cloud Run (`jobs:run`) via OAuth token | ✅ Terraform | `modules/compute` → `google_project_iam_member.job_invoker` |

> **Note** : si `TF_VAR_scheduler_service_account_email` est vide, `infra/main.tf` utilise `ingestion-sa` à la place. Dans ce cas, `ingestion-sa` reçoit ce rôle supplémentaire. Pour isoler les responsabilités, créer un `scheduler-sa` dédié est recommandé.

**Commande gcloud équivalente** :

```bash
SA="scheduler-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/run.invoker"
```

---

## 6. IAM Bindings — `terraform-deployer-sa`

Ce SA est utilisé par Terraform (CI GitHub Actions via WIF, ou ADC en local). Il a besoin de droits élevés pour gérer les ressources GCP.

| Rôle | Portée | Ressource cible | Pourquoi | Statut |
|------|--------|-----------------|----------|--------|
| `roles/storage.admin` | Projet | — | Créer / configurer le bucket raw + le bucket tfstate | 🔧 Manuel |
| `roles/bigquery.admin` | Projet | — | Créer / configurer les datasets BigQuery | 🔧 Manuel |
| `roles/run.admin` | Projet | — | Déployer le Cloud Run Job (INFRA-04) | 🔧 Manuel ❌ à faire |
| `roles/cloudscheduler.admin` | Projet | — | Créer / modifier les 3 jobs Cloud Scheduler (INFRA-05) | 🔧 Manuel ❌ à faire |
| `roles/secretmanager.admin` | Projet | — | Créer les secret containers Secret Manager (INFRA-06) | 🔧 Manuel ❌ à faire |
| `roles/iam.serviceAccountUser` | SA Resource | `ingestion-sa` | Assigner `ingestion-sa` comme `service_account` du Cloud Run Job | 🔧 Manuel ❌ à faire |

**Commandes gcloud** — rôles déjà accordés (INFRA-01/02/03) :

```bash
TF_SA="terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/bigquery.admin"
```

**Commandes gcloud** — rôles manquants pour INFRA-04/05/06 (❌ à exécuter) :

```bash
TF_SA="terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"
INGESTION_SA="ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com"

# Cloud Run (INFRA-04)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/run.admin"

# Cloud Scheduler (INFRA-05)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/cloudscheduler.admin"

# Secret Manager (INFRA-06)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/secretmanager.admin"

# Permet à terraform-deployer-sa d'assigner ingestion-sa au Cloud Run Job
gcloud iam service-accounts add-iam-policy-binding ${INGESTION_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${PROJECT}
```

> **En CI (GitHub Actions WIF)** : remplacer `terraform-deployer-sa` par le SA WIF configuré dans le workflow (`GCP_WIF_SERVICE_ACCOUNT`). Les mêmes rôles s'appliquent.

---

## 7. Rôles refusés / non accordés (principe du moindre privilège)

| Compte | Rôle interdit | Raison |
|--------|---------------|--------|
| `ingestion-sa` | `roles/bigquery.dataEditor` sur `staging` / `marts` | L'ingestion n'écrit que dans `raw`. Les autres datasets sont réservés à dbt. |
| `ingestion-sa` | `roles/storage.admin` | L'accès `objectAdmin` au bucket suffit. `storage.admin` donnerait la gestion de la config du bucket elle-même. |
| `dbt-sa` | `roles/bigquery.dataEditor` sur `raw` | dbt ne doit qu'écrire dans `staging` et `marts`. `raw` est en lecture seule pour lui. |
| `dashboard-sa` | `roles/bigquery.dataEditor` sur `marts` | Le dashboard n'a besoin que de lire. Accorder `dataEditor` créerait un risque d'écriture involontaire. |
| `dashboard-sa` | Tout accès à `raw` / `staging` | Le dashboard ne doit voir que les données finales de `marts`. |
| `scheduler-sa` | `roles/run.admin` | `run.invoker` suffit pour déclencher un job existant. `run.admin` permettrait de modifier le job. |
| Tout SA | `roles/owner` / `roles/editor` | Jamais de rôles primitifs larges sur un compte de service applicatif. |

---

## 8. Récapitulatif — état global

| SA | Création | Permissions core | Statut global |
|----|----------|------------------|---------------|
| `ingestion-sa` | ✅ Créé | Storage objectAdmin ✅ + BQ dataEditor(raw) ✅ + BQ jobUser ✅ + Secret Accessor FT_* ✅ + Secret Accessor DATAGOUV ❌ | ⚠️ Presque complet — créer DATAGOUV_API_KEY secret + binding |
| `dbt-sa` | ✅ Créé | BQ dataViewer(raw) + BQ dataEditor(staging,marts) + BQ jobUser ✅ | ✅ Géré Terraform (appliqué INFRA-03) |
| `dashboard-sa` | ✅ Créé | BQ dataViewer(marts) + BQ jobUser ✅ | ✅ Géré Terraform (appliqué INFRA-03) |
| `scheduler-sa` | ✅ Créé | run.invoker (projet) — binding appliqué par terraform apply INFRA-04 | ⏳ En attente terraform apply INFRA-04 |
| `terraform-deployer-sa` | ✅ Créé | storage.admin + bigquery.admin ✅ / run.admin + cloudscheduler.admin + secretmanager.admin + iam.serviceAccountUser ❌ | ⚠️ Incomplet pour INFRA-04/05/06 |

---

## 9. Notes importantes

### WIF (Workload Identity Federation)
En CI GitHub Actions, le workflow utilise WIF via `google-github-actions/auth@v2` et non une clé JSON. Le SA associé est `terraform-deployer-sa` (ou tout SA lié au WIF pool). Les rôles de la section 6 s'appliquent identiquement.

### Clés JSON
La création de clés JSON est bloquée par la policy org sur ce projet. Le mode recommandé est :
- **Local** : ADC (`gcloud auth application-default login`)
- **CI** : WIF

### `bq add-iam-policy-binding` — limitation connue
La commande `bq add-iam-policy-binding` pour les bindings **au niveau dataset** retourne `This feature requires allowlisting` sur GCP sans demande préalable. **Ne pas utiliser.** Les bindings dataset (`dataEditor`, `dataViewer`) sont gérés exclusivement par Terraform via `google_bigquery_dataset_iam_member`.

### Bindings idempotents via gcloud
Les commandes `add-iam-policy-binding` sont idempotentes — les relancer sur un binding déjà existant ne crée pas de doublon.

### Vérifier les bindings existants

```bash
# Tous les bindings du projet
gcloud projects get-iam-policy cartographie-data-engineer \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)"

# Bindings d'un SA spécifique
gcloud projects get-iam-policy cartographie-data-engineer \
  --flatten="bindings[].members" \
  --filter="bindings.members:ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
```
