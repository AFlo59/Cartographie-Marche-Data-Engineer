# Flux Infrastructure & Terraform

## Vue d'ensemble

Ce document explique comment les données circulent dans notre pipeline d'infrastructure, de GitHub Actions jusqu'à GCP.

### Architecture ingestion retenue

- 1 Cloud Run Job : `datatalent-ingestion-job`
- 3 Cloud Scheduler jobs : `france_travail`, `sirene`, `geo`
- Chaque Scheduler déclenche le même job avec `INGESTION_SOURCE=<source>` (override env via `jobsExecutorWithOverrides`)

Ce modèle est le plus simple et le moins coûteux en exploitation pour ce type de fréquence (quotidien/mensuel).

---

## 1. Sources des données

### GitHub Secrets / Variables (conteneur sécurisé)

Définis dans : `GitHub > Settings > Secrets and variables > Actions`

```yaml
GCP_PROJECT_ID       # Identifie le projet GCP cible
GCP_WIF_PROVIDER     # Pool d'identités WIF (format : projects/<num>/locations/global/workloadIdentityPools/...)
GCP_WIF_SERVICE_ACCOUNT  # SA WIF (ex : terraform-deployer-sa@<project>.iam.gserviceaccount.com)
```

### Env vars du Workflow (`infra-deploy.yml`)

Ces variables sont définies dans le workflow pour contrôler la configuration Terraform. Toutes préfixées `TF_VAR_` (lues automatiquement par Terraform).

Variables clés (valeurs non sensibles codées en dur dans le workflow, valeurs sensibles depuis Secrets) :

```yaml
TF_VAR_project_id:    <depuis GCP_PROJECT_ID>
TF_VAR_region:        europe-west1
TF_VAR_location:      EU
TF_VAR_environment:   dev
TF_VAR_project_prefix: datatalent

# Lifecycle bucket raw
TF_VAR_bucket_nearline_age_days:                  "30"   # Transition NEARLINE à 30j
TF_VAR_bucket_geo_prefix_delete_age_days:         "60"   # Purge auto geo/ à 60j
TF_VAR_bucket_sirene_prefix_delete_age_days:      "60"   # Purge auto sirene/ à 60j
TF_VAR_bucket_france_travail_prefix_delete_age_days: "60" # Purge auto france_travail/ à 60j

# Activation features (toutes actives en CI)
TF_VAR_create_compute_job:    "true"   # Cloud Run Job ingestion actif
TF_VAR_create_dbt_job:        "true"   # Cloud Run Job dbt actif
TF_VAR_create_external_tables: "true"  # External Tables BQ actives

# Artifact Registry cleanup
TF_VAR_artifact_registry_keep_recent_versions: "2"  # garder latest + 1 version précédente

# Cloud Logging retention
TF_VAR_manage_log_retention: "true"
TF_VAR_log_retention_days:   (valeur par défaut dans variables.tf)

# Backend Terraform (bucket tfstate)
TF_BACKEND_BUCKET:  datatalent-tfstate-<project_id>
```

---

## 2. Flux d'exécution CI/CD

### Phase 1 : Authentification

```
GitHub Actions Secret (GCP_WIF_PROVIDER + GCP_WIF_SERVICE_ACCOUNT)
    ↓
google-github-actions/auth@v3 (WIF)
    ↓
Token GCP temporaire (validité : 1h) — pas de clé JSON
```

### Phase 2 : Terraform Init

```
terraform init -backend-config="bucket=${TF_BACKEND_BUCKET}"
  ├─ Authentifie via WIF token
  └─ Télécharge terraform.tfstate depuis le bucket GCS
```

Le bucket tfstate est créé automatiquement par le workflow s'il est absent (step "Ensure Terraform backend bucket exists"), avec versioning activé et lifecycle `numNewerVersions=2` (conserve live + 1 version précédente).

### Phase 3 : Terraform Plan / Apply

```
terraform plan/apply
  ├─ Lit TF_VAR_* depuis env du workflow
  ├─ Compare avec le state GCS
  ├─ Interroge GCP ("ça existe vraiment ?")
  └─ Génère le plan ou applique
```

Un step d'import automatique (`import_if_needed`) adopte les ressources existantes dans le state avant l'apply, évitant les erreurs `409 already exists` :

- `module.storage.google_storage_bucket.raw`
- `module.warehouse.google_bigquery_dataset.*` (raw, staging, marts)
- `module.secrets.google_secret_manager_secret.secrets["*"]`
- `module.compute.google_artifact_registry_repository.datatalent`
- `module.compute.google_cloud_run_v2_job.ingestion[0]`
- `module.compute.google_cloud_run_v2_job.dbt[0]`
- `module.compute.google_logging_project_bucket_config.default_retention[0]`
- `module.scheduler[0].google_cloud_scheduler_job.ingestion["*"]`

---

## 3. Flux complet par déclencheur

### Cas 1 : Pull Request sur `develop` ou `main`

```
PR créée
    ↓
ingestion-verify (build Dockerfile ingestion — vérification validité)  ──┐
dbt-verify (build dbt + dbt parse + dbt compile)                       ──┤
                                                                          ↓
terraform [needs: verify jobs]
  1. Check secrets CI
  2. Auth GCP via WIF
  3. Setup gcloud
  4. Vérifier bucket tfstate (erreur si absent)
  5. terraform init + validate
  6. terraform plan
  7. Post plan en commentaire PR ✅

push-images : SKIPPED sur PR
```

### Cas 2 : Push sur `develop`

```
Push develop
    ↓
ingestion-verify + dbt-verify (parallèles)
    ↓
terraform
  1. Auth GCP + setup gcloud
  2. Activer APIs (best effort)
  3. Créer bucket tfstate si absent
  4. terraform init + validate
  (PAS de plan, PAS d'apply sur develop)

push-images : SKIPPED sur develop
```

### Cas 3 : Push sur `main`

```
Push main
    ↓
┌───────────────────────────┐    ┌────────────────────────────────────┐
│ ingestion-verify          │    │ dbt-verify                         │
│ • docker build ingestion  │    │ • Auth GCP via WIF                 │
│   (vérification validité) │    │ • docker build dbt image           │
└───────────────────────────┘    │ • dbt parse                        │
                                  │ • dbt compile                      │
                                  └────────────────────────────────────┘
             ↓ needs: [ingestion-verify, dbt-verify]
┌────────────────────────────────────────────────────────────────────┐
│ terraform                                                          │
│  1. Check secrets CI (fail-fast)                                   │
│  2. Auth GCP via WIF                                               │
│  3. Setup gcloud                                                   │
│  4. Activer APIs GCP manquantes (best effort)                      │
│  5. Créer bucket tfstate si absent + lifecycle (2 versions)        │
│  6. terraform init + validate                                      │
│  7. Vérifier APIs GCP requises (bloquant)                          │
│  8. terraform import existing resources (best effort)              │
│  9. terraform apply -auto-approve                                  │
└────────────────────────────────────────────────────────────────────┘
             ↓ needs: [terraform], main seulement
┌────────────────────────────────────────────────────────────────────┐
│ push-images                                                        │
│  1. Auth GCP via WIF                                               │
│  2. Configure Docker pour Artifact Registry                        │
│  3. Build + push ingestion:latest et ingestion:<sha8>              │
│  4. Build + push dbt:latest et dbt:<sha8>                          │
└────────────────────────────────────────────────────────────────────┘
```

---

## 4. Architecture GCP — ressources créées par Terraform

```
                      GITHUB ACTIONS
                           │
                    WIF → SA WIF token
                           │
                    terraform apply
                           │
    ┌──────────────────────┴───────────────────────┐
    │                   GCP                         │
    │                                               │
    │  Cloud Storage                                │
    │  └─ Bucket raw (lifecycle)                    │
    │     ├─ Nearline après 30j                     │
    │     ├─ Purge france_travail/ à 60j            │
    │     ├─ Purge sirene/ à 60j                    │
    │     ├─ Purge geo/ à 60j                       │
    │     └─ Suppression globale à 365j             │
    │                                               │
    │  BigQuery                                     │
    │  ├─ Dataset raw (External Tables GCS)         │
    │  │  ├─ sirene_etablissements                  │
    │  │  ├─ sirene_unites_legales                  │
    │  │  └─ france_travail_offres                  │
    │  ├─ Dataset staging (tables BQ réelles)       │
    │  └─ Dataset marts  (tables BQ réelles)        │
    │                                               │
    │  Artifact Registry                            │
    │  └─ repo datatalent (Docker)                  │
    │     ├─ ingestion:latest + ingestion:<sha8>    │
    │     ├─ dbt:latest + dbt:<sha8>                │
    │     └─ cleanup: garder 2 versions / image     │
    │                                               │
    │  Cloud Run Jobs                               │
    │  ├─ datatalent-ingestion-job (Python)         │
    │  └─ datatalent-dbt-job (dbt)                  │
    │                                               │
    │  Cloud Scheduler (déclenche ingestion-job)    │
    │  ├─ datatalent-ingestion-france_travail       │
    │  │  (0 6 * * * — quotidien, Europe/Paris)     │
    │  ├─ datatalent-ingestion-sirene               │
    │  │  (0 3 1 * * — mensuel)                     │
    │  └─ datatalent-ingestion-geo                  │
    │     (0 4 1 * * — mensuel)                     │
    │                                               │
    │  Secret Manager                               │
    │  ├─ FT_CLIENT_ID                              │
    │  ├─ FT_CLIENT_SECRET                          │
    │  └─ DATAGOUV_API_KEY                          │
    │                                               │
    │  Cloud Logging                                │
    │  └─ Bucket _Default : rétention 60j           │
    │                                               │
    └───────────────────────────────────────────────┘
```

---

## 5. Fichiers clés

| Fichier | Rôle |
|---------|------|
| `.github/workflows/infra-deploy.yml` | Orchestration CI/CD : 4 jobs (verify × 2, terraform, push-images) |
| `infra/variables.tf` | Structure des inputs Terraform + valeurs par défaut |
| `infra/main.tf` | Logique principale, wiring des modules |
| `infra/versions.tf` | Providers + backend GCS (bucket passé dynamiquement) |
| `infra/modules/compute/main.tf` | AR repo + Cloud Run Jobs + time_sleep 90s IAM propagation + log retention |
| `infra/modules/storage/main.tf` | Bucket raw + lifecycle (Nearline, purge par préfixe) |
| `infra/modules/warehouse/main.tf` | Datasets BQ + External Tables |
| `infra/modules/scheduler/main.tf` | Cloud Scheduler (3 jobs) |
| `infra/modules/secrets/main.tf` | Secret Manager containers + IAM accessor |
| `infra/terraform.tfvars.example` | Template vars locales (ne pas commiter `terraform.tfvars`) |
| `.env.example` | Template variables d'environnement (copier vers `.env`) |

---

## 6. Flux des secrets

```
GitHub Secrets (chiffrés)
  GCP_PROJECT_ID / GCP_WIF_PROVIDER / GCP_WIF_SERVICE_ACCOUNT
         ↓
  google-github-actions/auth@v3
         ↓
  Token GCP temporaire dans GOOGLE_APPLICATION_CREDENTIALS
         ↓
  Terraform init / plan / apply — utilise ce token
  gcloud CLI — utilise ce token
```

Les secrets applicatifs (`FT_CLIENT_ID`, `FT_CLIENT_SECRET`) sont stockés dans **GCP Secret Manager** et injectés dans le Cloud Run Job par Terraform via `secret_key_ref`. Les scripts d'ingestion ne lisent jamais les secrets depuis des fichiers.

---

## 7. Terraform state

### Backend dynamique

```bash
terraform init -backend-config="bucket=${TF_BACKEND_BUCKET}"
```

Le nom du bucket est passé dynamiquement depuis la CI (`TF_BACKEND_BUCKET` dans le workflow env).
Le fichier `versions.tf` ne contient pas de bucket hardcodé.

### Versioning et lifecycle du bucket tfstate

- Versioning activé (permet rollback)
- Lifecycle : `numNewerVersions=2` → supprime les versions archivées quand 2+ versions plus récentes existent (conserve live + 1 précédente)

---

## 8. Sécurité

- Secrets stockés chiffrés dans GitHub (jamais dans le code)
- WIF : pas de clé JSON (échange de token temporaire)
- SA avec permissions IAM minimales (principe du moindre privilège)
- State file en GCS (jamais dans git)
- `.gitignore` exclut `*.tfvars`, `.terraform/`, `.env`
- `terraform.tfvars` : ne jamais commiter — copier depuis `terraform.tfvars.example`

---

## 9. Troubleshooting

### "Terraform backend bucket is missing"

Le bucket tfstate n'existe pas. Créer une fois depuis Cloud Shell :

```bash
TF_BACKEND_BUCKET="datatalent-tfstate-${GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION:-europe-west1}"
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud storage buckets create gs://${TF_BACKEND_BUCKET} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --uniform-bucket-level-access

gcloud storage buckets update gs://${TF_BACKEND_BUCKET} --versioning
```

Le workflow CI recrée automatiquement le bucket s'il est absent sur push `main`/`develop`.

### "Missing GitHub Actions secret"

`GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, ou `GCP_WIF_SERVICE_ACCOUNT` manquant.
GitHub > Settings > Secrets and variables > Actions > créer les 3 entrées.

### "Permission denied" lors du apply

Le SA WIF n'a pas tous les rôles nécessaires. Voir [docs/infra/iam_roles.md](iam_roles.md) section 6.

### "403 artifactregistry.repositories.downloadArtifacts" lors de la création Cloud Run Job

GCP IAM prend jusqu'à 90s à propager les nouveaux bindings. Solution appliquée : `time_sleep` de 90s dans `infra/modules/compute/main.tf` avec `triggers` sur les IDs des bindings IAM. Aucune action manuelle nécessaire — le prochain apply passera.

### "403 logging.buckets.create" lors du apply

Le SA WIF n'a pas `roles/logging.configWriter`. Voir [docs/infra/iam_roles.md](iam_roles.md) section 6.

---

## 10. Résumé rapide

| Composant | Localisation | Contenu |
|-----------|--------------|---------|
| Secrets CI | GitHub Secrets | GCP_PROJECT_ID, WIF config |
| Env vars CI | `infra-deploy.yml` | TF_VAR_*, TF_BACKEND_BUCKET |
| Code Terraform | `infra/` | variables.tf, main.tf, modules/ |
| State file | GCS bucket tfstate | terraform.tfstate (JSON) |
| Images Docker | Artifact Registry `datatalent` | ingestion + dbt (2 versions max) |
| Ressources GCP | GCP | Storage + BQ + Cloud Run + Scheduler + Secrets + Logging |

---

**Dernière mise à jour** : Avril 2026
**Voir aussi** : [docs/cicd/deployment_orchestration.md](../cicd/deployment_orchestration.md)
