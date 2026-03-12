# Epic 4 — Statut des tickets INFRA

## Résumé

- ✅ **INFRA-01** : Choix du cloud (GCP) documenté dans le README.
- ✅ **INFRA-02** : Module bucket raw en place (`infra/modules/storage`) **et bucket créé dans GCP**.
- ✅ **INFRA-03** : Module datasets raw/staging/marts en place (`infra/modules/warehouse`) **et datasets créés dans GCP**.
- ✅ **INFRA-04** : Implémenté — module compute Cloud Run Job (`infra/modules/compute`) branché au root Terraform.
- ✅ **INFRA-05** : Implémenté — module scheduler (`infra/modules/scheduler`) avec 3 jobs cron (France Travail, Sirene, Géo).
- ✅ **INFRA-06** : Implémenté — module secrets (`infra/modules/secrets`) + bindings `secretAccessor` pour `ingestion-sa`.
- 🟡 **INFRA-07** : Partiel (IAM dataset et bucket en place, + BigQuery projet-level `roles/bigquery.jobUser`; IAM service accounts complet à finaliser).
- 🟡 **INFRA-08** : Non implémenté (`docs/cost_estimation.md` à créer).
- 🟡 **INFRA-09** : Partiel — workflow IaC ajouté (`.github/workflows/infra-deploy.yml`) avec WIF, plan PR, apply main; restent à ajouter lint Python + checks dbt (`compile/run/test`) pour couvrir le ticket backlog complet.
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

1. Exécuter `terraform init -migrate-state` pour backend GCS si pas encore fait.
2. Appliquer Terraform pour créer les nouvelles ressources INFRA-04/05/06 dans GCP.
3. Vérifier l'existence de l'image `TF_VAR_compute_image` (Cloud Run Job).
4. Finaliser IAM par rôles de service account dédiés si besoin de durcissement.
5. Compléter INFRA-09 (lint Python + dbt compile sur PR, puis dbt run/test sur merge main).

## CI Security

- Workflow CodeQL ajouté : `.github/workflows/codeql.yml`
- Couvre `push` et `pull_request` sur `main`/`develop` + scan hebdomadaire.

## Validation exécution (INFRA-01/02/03)

- `terraform plan` et `terraform apply` exécutés avec succès via le conteneur `infra-iac`.
- Outputs Terraform confirmés:
  - Bucket: `datatalent-dev-cartographie-data-engineer-raw`
  - Datasets: `raw`, `staging`, `marts`
- Vérification GCP confirmée via `gcloud storage buckets list` et `bq ls`.
