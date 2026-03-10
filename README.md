# Cartographie-Marche-Data-Engineer

Pipeline de données end-to-end : cartographie du marché Data Engineer en France.

## Epic 4 — Démarrage infra (INFRA-01, INFRA-02, INFRA-03)

### Choix du cloud : GCP

Le projet démarre sur **Google Cloud Platform (GCP)** pour les raisons suivantes :

- Intégration native **Cloud Storage + BigQuery + Cloud Run + Cloud Scheduler**
- Très bon fit analytique pour ce cas d'usage (requêtes SQL, partitionnement, clustering)
- Démarrage rapide via free tier / crédits de compte
- Bonne compatibilité Terraform/OpenTofu pour l'IaC

### Ressources couvertes dans ce repo

Cette première itération IaC provisionne :

- Un bucket raw GCS (module `infra/modules/storage`)
- Trois datasets BigQuery (`raw`, `staging`, `marts`) via module `infra/modules/warehouse`
- Des permissions IAM dataset-level paramétrables pour ingestion/dbt/dashboard
- Des permissions IAM projet-level BigQuery `roles/bigquery.jobUser` pour permettre l'exécution des jobs (requêtes/loads)

### Arborescence infra

```text
infra/
  main.tf
  providers.tf
  variables.tf
  outputs.tf
  versions.tf
  terraform.tfvars.example
  modules/
    storage/
    warehouse/
```

### Prérequis

- Terraform >= 1.6 (ou OpenTofu compatible)
- Un projet GCP existant
- APIs activées : `storage.googleapis.com`, `bigquery.googleapis.com`
- Auth locale GCP (ex: `gcloud auth application-default login`)

### Configuration locale (.env)

1. Copier `.env.example` en `.env`.

1. Renseigner au minimum les variables réellement utilisées par le flux Docker/Terraform : `TF_VAR_project_id`, `TF_VAR_region`, `TF_VAR_location`.

1. Les variables `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_LOCATION` sont conservées comme alias de lisibilité et pour les commandes/documentation GCP, mais ce sont bien les `TF_VAR_*` qui pilotent l'exécution Terraform.

1. Auth Docker recommandée (par défaut) : `gcloud auth login` + `gcloud auth application-default login` dans le conteneur (ADC). Dans ce mode, **aucun fichier clé JSON n'est requis**.

1. Auth Docker alternative (optionnelle, si policy autorise les clés) : définir `GOOGLE_APPLICATION_CREDENTIALS=/workspace/secrets/gcp-sa.json` et placer la clé dans `secrets/gcp-sa.json`.

1. Les autres `TF_VAR_*` (`environment`, `project_prefix`, datasets, emails SA, etc.) permettent de compléter le paramétrage de l'infra.

1. Nom du bucket raw : par défaut, le nom est calculé automatiquement avec une logique compatible limite GCS (63 caractères max, avec troncature + suffixe hash si nécessaire). Pour forcer un nom explicite globalement unique, définir `TF_VAR_raw_bucket_name`.

### Dépendances Python

Le fichier `requirements.txt` est prêt pour les scripts d'ingestion (API + GCS + BigQuery).

Exemple d'installation :

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### Exécuter l'IaC dans un conteneur dédié

Le projet inclut un conteneur `infra-iac` (Terraform + OpenTofu + gcloud) pour éviter d'installer ces outils en local.

Lancer les commandes depuis la racine du repo :

```bash
cd D:/PROJETS/Cartographie-Marche-Data-Engineer
```

Vérifier que `.env` existe (sinon copier `.env.example`) :

```bash
ls -l .env
```

Deux chemins d'authentification sont supportés :

- Option A (token OAuth) : robuste en cas d'échec ADC
- Option B (ADC) : mode standard

Par défaut, `docker-compose.yml` utilise `GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json` (ADC). Vous ne devez configurer `secrets/gcp-sa.json` que si vous choisissez explicitement le mode clé JSON.

Option A — Token OAuth :

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform init -backend=false && terraform validate && terraform plan'
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform apply'
```

Option B — ADC :

```bash
docker compose build infra-iac
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac terraform init -backend=false
docker compose run --rm infra-iac terraform validate
docker compose run --rm infra-iac terraform plan
docker compose run --rm infra-iac terraform apply
```

Validation/FMT :

```bash
docker compose run --rm infra-iac terraform fmt -check -recursive
docker compose run --rm infra-iac terraform validate
```

Le statut détaillé des tickets Epic 4 est suivi dans `docs/infra_epic4_status.md`.

Le guide des commandes Cloud Shell (setup projet, service accounts, récupération des infos `.env`) est disponible dans `docs/gcp_terminal_setup.md`.

Le guide des commandes Docker (run du conteneur infra) est disponible dans `docs/docker_run_commands.md`.

Le guide des commandes manuelles (terminal local + Cloud Shell) est disponible dans `docs/manual_commands.md`.

### Déploiement (exemple)

```bash
cd infra
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Copier `infra/terraform.tfvars.example` vers `infra/terraform.tfvars` puis renseigner les variables.

## Prochaines étapes

- INFRA-04 à INFRA-07 : compute serverless, scheduler, secrets, IAM avancé
- INFRA-09 : pipelines CI/CD GitHub Actions
- Intégration des modules infra avec l'ingestion et dbt

