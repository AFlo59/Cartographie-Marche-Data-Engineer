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

