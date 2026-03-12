# Cartographie-Marche-Data-Engineer

Pipeline de données end-to-end : cartographie du marché Data Engineer en France.

## Epic 4 — État infra actuel (INFRA-01 à INFRA-06 + INFRA-09 partiel)

### Choix du cloud : GCP

Le projet démarre sur **Google Cloud Platform (GCP)** pour les raisons suivantes :

- Intégration native **Cloud Storage + BigQuery + Cloud Run + Cloud Scheduler**
- Très bon fit analytique pour ce cas d'usage (requêtes SQL, partitionnement, clustering)
- Démarrage rapide via free tier / crédits de compte
- Bonne compatibilité Terraform/OpenTofu pour l'IaC

### Ressources couvertes dans ce repo

Cette itération IaC provisionne :

- Un bucket raw GCS (module `infra/modules/storage`)
- Trois datasets BigQuery (`raw`, `staging`, `marts`) via module `infra/modules/warehouse`
- Un Cloud Run Job d'ingestion (module `infra/modules/compute`)
- Trois jobs Cloud Scheduler (module `infra/modules/scheduler`)
- Les secrets API dans Secret Manager + binding `secretAccessor` ingestion (module `infra/modules/secrets`)
- Les IAM dataset-level et `roles/bigquery.jobUser` pour ingestion/dbt/dashboard
- Un workflow CI infra WIF (`.github/workflows/infra-deploy.yml`) pour plan/apply Terraform

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
    compute/
    scheduler/
    secrets/
```

### Documentation d'entrée

Le point d'entrée principal de la documentation infra est : [docs/setup_guide.md](docs/setup_guide.md)

Cette structure évite les doublons et sépare les parcours :

- [docs/gcp_terminal_setup.md](docs/gcp_terminal_setup.md) pour le setup manuel GCP,
- [docs/docker_run_commands.md](docs/docker_run_commands.md) pour l'exécution via Docker,
- [docs/manual_commands.md](docs/manual_commands.md) pour l'exécution avec outils installés localement,
- [docs/secret_manager_setup.md](docs/secret_manager_setup.md) pour les secrets runtime,
- [docs/github_wif_setup.md](docs/github_wif_setup.md) pour la CI GitHub ↔ GCP,
- [docs/iam_roles.md](docs/iam_roles.md) pour les rôles et permissions.

### Dépendances Python

Le fichier `requirements.txt` est prêt pour les scripts d'ingestion (API + GCS + BigQuery).

Exemple d'installation :

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### Exécuter l'IaC

Le projet inclut un conteneur `infra-iac` pour éviter d'installer Terraform/OpenTofu/gcloud localement.

Le chemin principal de déploiement visé dans le périmètre infra actuel est le workflow GitHub Actions après merge sur `main` pour l'infrastructure Terraform.
Les exécutions Docker et terminal local servent surtout au développement, à la validation manuelle et au debug.

Deux parcours sont documentés séparément :

- via Docker : [docs/docker_run_commands.md](docs/docker_run_commands.md)
- via outils installés localement : [docs/manual_commands.md](docs/manual_commands.md)

Le statut détaillé des tickets Epic 4 reste suivi dans [docs/infra_epic4_status.md](docs/infra_epic4_status.md).

### Déploiement (exemple)

```bash
cd infra
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Copier `infra/terraform.tfvars.example` vers `infra/terraform.tfvars` puis renseigner les variables.

## Prochaines étapes

- INFRA-07 : finaliser le durcissement IAM (moindre privilège)
- INFRA-08 : document de coûts `docs/cost_estimation.md`
- INFRA-09 : compléter CI avec lint Python + dbt (compile/run/test)
- Intégration applicative ingestion/dbt sur les ressources désormais provisionnées

