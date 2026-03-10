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

1. Renseigner au minimum : `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_LOCATION`, `GOOGLE_APPLICATION_CREDENTIALS` (chemin local vers la clé JSON du service account).

1. Les variables `TF_VAR_*` dans `.env` permettent d'alimenter Terraform automatiquement.

### Dépendances Python

Le fichier `requirements.txt` est prêt pour les scripts d'ingestion (API + GCS + BigQuery).

Exemple d'installation :

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### Exécuter l'IaC dans un conteneur dédié

Le projet inclut un conteneur `infra-iac` (Terraform + OpenTofu) pour éviter d'installer ces outils en local.

Préparer les secrets :

- Créer un dossier `secrets/`
- Ajouter la clé JSON du service account GCP dans `secrets/gcp-sa.json`

Commandes principales :

```bash
docker compose build infra-iac
docker compose run --rm infra-iac terraform init
docker compose run --rm infra-iac terraform plan
docker compose run --rm infra-iac terraform apply
```

Validation/FMT :

```bash
docker compose run --rm infra-iac fmt -check
docker compose run --rm infra-iac validate
```

Le statut détaillé des tickets Epic 4 est suivi dans `docs/infra_epic4_status.md`.

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

