# Epic 4 — Statut des tickets INFRA

## Résumé

- ✅ **INFRA-01** : Choix du cloud (GCP) documenté dans le README.
- ✅ **INFRA-02** : Module bucket raw (`infra/modules/storage`) et bucket créé dans GCP. Lifecycle enrichi :
  - Transition NEARLINE à 30j (~40% d'économie Sirene)
  - **Purge automatique par préfixe à 60j** (france_travail, sirene, geo) — conserve latest + 1 snapshot mensuel précédent
  - Suppression globale à 365j (filet de sécurité)
- ✅ **INFRA-03** : Module datasets raw/staging/marts (`infra/modules/warehouse`) et datasets créés dans GCP. 3 External Tables BigQuery définies : `sirene_etablissements`, `sirene_unites_legales`, `france_travail_offres` — pointent sur les Parquet GCS, aucun stockage BQ facturé pour les données raw. Activation conditionnée par `var.create_external_tables` (passé `true` en CI après première ingestion).
- ✅ **INFRA-04** : Module compute Cloud Run Job (`infra/modules/compute`).
  - **Cloud Run Job ingestion** (`datatalent-ingestion-job`) : **ACTIF** en CI (`TF_VAR_create_compute_job=true`)
  - **Cloud Run Job dbt** (`datatalent-dbt-job`) : **ACTIF** en CI (`TF_VAR_create_dbt_job=true`)
  - `time_sleep` 90s avant création des jobs (propagation IAM)
  - Artifact Registry repo `datatalent` avec cleanup policy : **garder 2 versions** (latest + précédente), supprimer les autres après 7 jours
  - **Rétention logs Cloud Logging** : bucket `_Default` configuré à 60j (`TF_VAR_manage_log_retention=true`)
  - CI SA reçoit `roles/artifactregistry.writer` et `roles/iam.serviceAccountUser` via Terraform
- ✅ **INFRA-05** : Module scheduler (`infra/modules/scheduler`) avec 3 jobs cron actifs :
  - France Travail quotidien `0 6 * * *`
  - Sirene mensuel `0 3 1 * *`
  - Géo mensuel `0 4 1 * *`
  - Scheduler conditionné par `var.create_compute_job` (actif)
- ✅ **INFRA-06** : Module secrets (`infra/modules/secrets`) + bindings `secretAccessor` pour `ingestion-sa`.
- ✅ **INFRA-07** : IAM complet — IAM datasets BQ + bucket raw + BQ jobUser + Artifact Registry pour tous les SA. `roles/storage.objectViewer` pour `dbt-sa` (requis pour External Tables). Voir [docs/infra/iam_roles.md](iam_roles.md).
- 🟡 **INFRA-08** : Non implémenté (`docs/cost_estimation.md` à créer). Estimation cible : < 5€/mois hors free tier GCP.
- 🟡 **INFRA-09** : Partiel — workflow IaC (`.github/workflows/infra-deploy.yml`) avec WIF, plan PR, apply main, gate ingestion (`docker build`) + gate dbt (`parse`/`compile`) avant Terraform, puis `push-images` (ingestion + dbt). Restent : lint Python et `dbt run/test` sur merge `main`.
- ✅ **INFRA-10** : Partiellement couvert (structure repo + `.gitignore` + `.env.example` créés ; branch protection à configurer sur GitHub UI).

---

## Architecture CI/CD actuelle — workflow `infra-deploy.yml`

Le workflow orchestre en **4 jobs** sur push `main` :

```
push main
    ├──► ingestion-verify  ──────────────┐
    │    (docker build ingestion)        ├──► terraform (apply) ──► push-images
    └──► dbt-verify  ───────────────────-┘    (AR + jobs + IAM)     (ingestion:latest
         (build dbt + parse + compile)                               + dbt:latest → AR)
```

| Job | Rôle | Condition |
|-----|------|-----------|
| `ingestion-verify` | Build Dockerfile ingestion (vérification validité) | Toujours |
| `dbt-verify` | Build image dbt + `dbt parse` + `dbt compile` | Toujours |
| `terraform` | `terraform apply` — bloqué si verify échoue | needs: [ingestion-verify, dbt-verify] |
| `push-images` | Build + push `ingestion:latest` et `dbt:latest` vers AR | needs: [terraform], main seulement |

Sur **PR** : verify + plan (pas d'apply, pas de push images).
Sur **push develop** : verify + init + validate (pas de plan, pas d'apply).

---

## Variables Terraform actives en CI (`infra-deploy.yml`)

| Variable | Valeur en CI | Description |
|----------|-------------|-------------|
| `TF_VAR_create_compute_job` | `"true"` | Cloud Run Job ingestion actif |
| `TF_VAR_create_dbt_job` | `"true"` | Cloud Run Job dbt actif |
| `TF_VAR_create_external_tables` | `"true"` | External Tables BQ actives |
| `TF_VAR_manage_log_retention` | `"true"` | Rétention logs 60j gérée par Terraform |
| `TF_VAR_bucket_*_prefix_delete_age_days` | `"60"` | Purge auto par préfixe à 60j |
| `TF_VAR_bucket_nearline_age_days` | `"30"` | Transition NEARLINE à 30j |
| `TF_VAR_artifact_registry_keep_recent_versions` | `2` | Garder latest + 1 version précédente |

---

## Détail infra conteneurisée

Trois conteneurs sont disponibles dans `docker-compose.yml` :

- `infra-iac` : `infra/Dockerfile` — image outillée (`terraform` + `tofu` + `gcloud`) pour exécuter l'IaC
- `ingestion-jobs` : `src/ingestion/Dockerfile` — image Python pour les scripts d'ingestion (`france_travail`, `sirene`, `geo`, `all`)
- `dbt` (profile dbt) : `dbt/transformation/Dockerfile` — image dbt-bigquery pour les transformations

Guides d'exécution :

- [docs/infra/docker_run_commands.md](docker_run_commands.md) — commandes via Docker (infra-iac)
- [docs/infra/manual_commands.md](manual_commands.md) — commandes manuelles local/Cloud Shell
- [docs/ingestion/ingestion_docker.md](../ingestion/ingestion_docker.md) — commandes ingestion Docker
- [docs/dbt/docker_run_commands.md](../dbt/docker_run_commands.md) — commandes dbt Docker

---

## Actions restantes

### IAM manquant — `roles/logging.configWriter` sur SA WIF

**Cause** : Terraform gère la rétention du bucket `_Default` Cloud Logging (`TF_VAR_manage_log_retention=true`).
Le SA WIF (`${GCP_WIF_SERVICE_ACCOUNT}`) n'a pas `roles/logging.configWriter` → erreur 403 lors du `terraform apply`.

**Fix — exécuter une seule fois depuis Cloud Shell** :

```bash
TF_SA="$(gcloud config get account)"   # ou l'email exact du SA WIF
PROJECT="$(gcloud config get project)"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/logging.configWriter"
```

Puis relancer le workflow (`workflow_dispatch` ou push).

### Prochaines étapes INFRA-09 (qualité CI)

1. Ajouter lint Python (`ruff` ou `flake8`) dans le workflow CI.
2. Ajouter `dbt run` + `dbt test` sur merge `main` (actuellement seulement `parse` + `compile`).

### INFRA-08 (coût)

Créer `docs/infra/cost_estimation.md` avec estimation Infracost ou manuelle.
Cible : < 5€/mois hors free tier GCP avec les optimisations en place.

---

## Validation exécution (INFRA-01/02/03/04/05/06/07)

- `terraform apply` exécuté avec succès via CI (push main).
- Outputs Terraform confirmés :
  - Bucket raw : `${TF_VAR_project_prefix}-${TF_VAR_environment}-${TF_VAR_project_id}-raw`
  - Datasets : `raw`, `staging`, `marts`
  - Cloud Run Jobs : `datatalent-ingestion-job`, `datatalent-dbt-job`
  - Schedulers : `datatalent-ingestion-france_travail`, `datatalent-ingestion-sirene`, `datatalent-ingestion-geo`
  - Artifact Registry : repo `datatalent` (region `${TF_VAR_region}`)

---

## CI Security

- Workflow CodeQL ajouté : `.github/workflows/codeql.yml`
- Couvre `push` et `pull_request` sur `main`/`develop` + scan hebdomadaire.

---

**Dernière mise à jour** : Avril 2026
