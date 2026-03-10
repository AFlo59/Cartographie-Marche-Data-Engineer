# Epic 4 — Statut des tickets INFRA

## Résumé

- ✅ **INFRA-01** : Choix du cloud (GCP) documenté dans le README.
- ✅ **INFRA-02** : Module bucket raw en place (`infra/modules/storage`) **et bucket créé dans GCP**.
- ✅ **INFRA-03** : Module datasets raw/staging/marts en place (`infra/modules/warehouse`) **et datasets créés dans GCP**.
- 🟡 **INFRA-04** : Non implémenté (module compute serverless à créer).
- 🟡 **INFRA-05** : Non implémenté (module scheduler à créer).
- 🟡 **INFRA-06** : Non implémenté (module Secret Manager à créer).
- 🟡 **INFRA-07** : Partiel (IAM dataset et bucket; IAM service accounts complet à faire).
- 🟡 **INFRA-08** : Non implémenté (`docs/cost_estimation.md` à créer).
- 🟡 **INFRA-09** : Non implémenté (workflows GitHub Actions à créer).
- ✅ **INFRA-10** : Partiellement couvert (structure repo + `.gitignore` + `.env.example` créés; branch protection à configurer sur GitHub UI).

## Détail infra conteneurisée

Un conteneur dédié IaC est disponible pour éviter une installation locale directe de Terraform/OpenTofu :

- `infra/Dockerfile` : image outillée (`terraform` + `tofu` + `gcloud`)
- `infra/scripts/entrypoint.sh` : commandes d'aide (`fmt`, `validate`)
- `docker-compose.yml` : service `infra-iac`

Guides d'exécution:

- `docs/docker_run_commands.md` (commandes via Docker)
- `docs/manual_commands.md` (commandes manuelles local/Cloud Shell)

## Actions restantes prioritaires

1. Créer `infra/modules/compute` (Cloud Run Job) + variables.
2. Créer `infra/modules/secrets` (Secret Manager) + binding au compute.
3. Créer `infra/modules/scheduler` (3 jobs cron France Travail / Sirene / Géo).
4. Finaliser IAM par rôles de service account dédiés.
5. Mettre en place CI/CD GitHub Actions (PR checks + main deploy).

## Validation exécution (INFRA-01/02/03)

- `terraform plan` et `terraform apply` exécutés avec succès via le conteneur `infra-iac`.
- Outputs Terraform confirmés:
	- Bucket: `datatalent-dev-cartographie-data-engineer-raw`
	- Datasets: `raw`, `staging`, `marts`
- Vérification GCP confirmée via `gcloud storage buckets list` et `bq ls`.
