# Epic 4 — Statut des tickets INFRA

## Résumé

- ✅ **INFRA-01** : Choix du cloud (GCP) documenté dans le README.
- ✅ **INFRA-02** : Module bucket raw (`infra/modules/storage`) **et bucket créé dans GCP**. Lifecycle enrichi : transition NEARLINE à 30j (~40% d'économie Sirene) + suppression préfixe geo/ à 90j (paramétrable via `var.ingestion_geo_prefix`).
- ✅ **INFRA-03** : Module datasets raw/staging/marts (`infra/modules/warehouse`) **et datasets créés dans GCP**. 3 External Tables BigQuery définies : `sirene_etablissements`, `sirene_unites_legales`, `france_travail_offres` — pointent sur les Parquet GCS, aucun stockage BQ facturé pour les données raw. Création conditionnée par `var.create_external_tables` (défaut `false`) : BigQuery nécessite au moins un fichier Parquet dans GCS pour `autodetect = true` — activer après la première ingestion.
- ✅ **INFRA-04** : Module compute Cloud Run Job (`infra/modules/compute`). **Création du job conditionnée par `var.create_job`** (défaut `false`) : GCP échoue avec 403 si l'image n'existe pas encore dans Artifact Registry. Le module Cloud Scheduler est également conditionné (`count = var.create_compute_job ? 1 : 0`). Les IAM bindings Artifact Registry sont créés inconditionnellement (préparés en avance). `time_sleep` de 90s (60s était insuffisant) + `coalesce(one(...), "")` pour les triggers. Provider `hashicorp/time ~> 0.9`.
- ✅ **INFRA-05** : Module scheduler (`infra/modules/scheduler`) avec 3 jobs cron (France Travail quotidien `0 6 * * *`, Sirene mensuel `0 3 1 * *`, Géo mensuel `0 4 1 * *`).
- ✅ **INFRA-06** : Module secrets (`infra/modules/secrets`) + bindings `secretAccessor` pour `ingestion-sa`.
- ✅ **INFRA-07** : IAM complet — IAM datasets BQ + bucket raw + BQ jobUser + Artifact Registry pour tous les SA. Ajout `roles/storage.objectViewer` pour `dbt-sa` (requis pour que BQ lise GCS lors des queries sur External Tables). Voir [docs/infra/iam_roles.md](iam_roles.md).
- 🟡 **INFRA-08** : Non implémenté (`docs/cost_estimation.md` à créer). Estimation cible : < 5€/mois hors free tier GCP avec les optimisations en place (Nearline, External Tables, 1 job mutualisé).
- 🟡 **INFRA-09** : Partiel — workflow IaC (`.github/workflows/infra-deploy.yml`) avec WIF, plan PR, apply main, et gate dbt (`parse`/`compile`) avant Terraform. Workflow dbt dédié ajouté (`.github/workflows/dbt-ci.yml`) sur `main`/`develop` (push + PR) pour `parse`/`compile`. Restent : lint Python et exécution dbt `run/test` sur merge `main`.
- ✅ **INFRA-10** : Partiellement couvert (structure repo + `.gitignore` + `.env.example` créés; branch protection à configurer sur GitHub UI).

## Détail infra conteneurisée

Trois conteneurs sont disponibles dans `docker-compose.yml` :

- `infra-iac` : `infra/Dockerfile` — image outillée (`terraform` + `tofu` + `gcloud`) pour exécuter l'IaC
- `ingestion` : `src/ingestion/Dockerfile` — image Python pour les scripts d'ingestion (squelette prêt, scripts à développer)
- `dbt` : `dbt/transformation/Dockerfile` — image dbt-bigquery pour les transformations

- `infra/scripts/entrypoint.sh` : commandes d'aide (`fmt`, `validate`)

Guides d'exécution:

- `docs/infra/docker_run_commands.md` (commandes via Docker)
- `docs/infra/manual_commands.md` (commandes manuelles local/Cloud Shell)

## Actions restantes prioritaires

1. **Pousser la branche** `feature_infra_04` sur `main` — `terraform apply` ne crée que bucket + datasets + IAM (compute et external tables désactivés par défaut).
2. **Développer les scripts d'ingestion** (`src/ingestion/`), builder et pusher l'image vers Artifact Registry, puis activer `TF_VAR_create_compute_job=true` dans le workflow CI.
3. **Activer les External Tables BQ** après la première ingestion : re-apply avec `TF_VAR_create_external_tables=true`. Voir [docs/infra/manual_commands.md](manual_commands.md#activer-les-external-tables-bigquery-après-la-première-ingestion).
4. **Compléter INFRA-09** : ajouter lint Python (`ruff`), puis `dbt run` + `dbt test` sur merge `main` (les checks `parse/compile` sont déjà en place).
5. **Créer `docs/cost_estimation.md`** (INFRA-08) — estimer les coûts avec Infracost ou manuellement.

## CI Security

- Workflow CodeQL ajouté : `.github/workflows/codeql.yml`
- Couvre `push` et `pull_request` sur `main`/`develop` + scan hebdomadaire.

## Validation exécution (INFRA-01/02/03)

- `terraform plan` et `terraform apply` exécutés avec succès via le conteneur `infra-iac`.
- Outputs Terraform confirmés:
  - Bucket: `datatalent-dev-cartographie-data-engineer-raw`
  - Datasets: `raw`, `staging`, `marts`
- Vérification GCP confirmée via `gcloud storage buckets list` et `bq ls`.
