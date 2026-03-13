# Epic 4 — Statut des tickets INFRA

## Résumé

- ✅ **INFRA-01** : Choix du cloud (GCP) documenté dans le README.
- ✅ **INFRA-02** : Module bucket raw (`infra/modules/storage`) **et bucket créé dans GCP**. Lifecycle enrichi : transition NEARLINE à 30j (~40% d'économie Sirene) + suppression préfixe geo/ à 90j (paramétrable via `var.ingestion_geo_prefix`).
- ✅ **INFRA-03** : Module datasets raw/staging/marts (`infra/modules/warehouse`) **et datasets créés dans GCP**. 3 External Tables BigQuery ajoutées dans le dataset `raw` : `sirene_etablissements`, `sirene_unites_legales`, `france_travail_offres` — pointent sur les Parquet GCS, aucun stockage BQ facturé pour les données raw.
- ✅ **INFRA-04** : Module compute Cloud Run Job (`infra/modules/compute`). **Bug 403 Artifact Registry corrigé** : `time_sleep` de 60s ajouté entre les bindings IAM Artifact Registry et la création du job (propagation IAM GCP asynchrone). Provider `hashicorp/time ~> 0.9` ajouté dans `versions.tf`.
- ✅ **INFRA-05** : Module scheduler (`infra/modules/scheduler`) avec 3 jobs cron (France Travail quotidien `0 6 * * *`, Sirene mensuel `0 3 1 * *`, Géo mensuel `0 4 1 * *`).
- ✅ **INFRA-06** : Module secrets (`infra/modules/secrets`) + bindings `secretAccessor` pour `ingestion-sa`.
- ✅ **INFRA-07** : IAM complet — IAM datasets BQ + bucket raw + BQ jobUser + Artifact Registry pour tous les SA. Ajout `roles/storage.objectViewer` pour `dbt-sa` (requis pour que BQ lise GCS lors des queries sur External Tables). Voir [docs/infra/iam_roles.md](iam_roles.md).
- 🟡 **INFRA-08** : Non implémenté (`docs/cost_estimation.md` à créer). Estimation cible : < 5€/mois hors free tier GCP avec les optimisations en place (Nearline, External Tables, 1 job mutualisé).
- 🟡 **INFRA-09** : Partiel — workflow IaC (`.github/workflows/infra-deploy.yml`) avec WIF, plan PR, apply main. Restent : lint Python + checks dbt (`compile/run/test`) sur PR.
- ✅ **INFRA-10** : Partiellement couvert (structure repo + `.gitignore` + `.env.example` créés; branch protection à configurer sur GitHub UI).

## Détail infra conteneurisée

Un conteneur dédié IaC est disponible pour éviter une installation locale directe de Terraform/OpenTofu :

- `infra/Dockerfile` : image outillée (`terraform` + `tofu` + `gcloud`)
- `infra/scripts/entrypoint.sh` : commandes d'aide (`fmt`, `validate`)
- `docker-compose.yml` : service `infra-iac`

Guides d'exécution:

- `docs/infra/docker_run_commands.md` (commandes via Docker)
- `docs/infra/manual_commands.md` (commandes manuelles local/Cloud Shell)

## Actions restantes prioritaires

1. **`terraform init`** en CI ou local pour télécharger le provider `hashicorp/time` (ajouté pour le fix 403). Le workflow CI l'exécute automatiquement à chaque run.
2. **Pousser la branche** `feature_infra_04` sur `main` — le prochain `terraform apply` passera (fix IAM propagation en place).
3. **Vérifier l'image** `TF_VAR_compute_image` dans Artifact Registry (`europe-west1-docker.pkg.dev/<project>/datatalent/ingestion:latest`) avant le apply.
4. **Compléter INFRA-09** : ajouter lint Python (`ruff`) + `dbt compile` sur les PRs, puis `dbt run` + `dbt test` sur merge main.
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
