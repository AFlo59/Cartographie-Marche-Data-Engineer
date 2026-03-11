# Commandes manuelles — local & Cloud Shell

A FAIRE EN PREMIER.
Ce fichier regroupe les commandes manuelles hors exécution Docker.

## A) Terminal local (PowerShell)

## 1) Vérifier le dossier projet

```powershell
Set-Location "D:\PROJETS\Cartographie-Marche-Data-Engineer"
```

But: se placer à la racine du repo.

## 2) Préparer le fichier d'environnement

```powershell
Copy-Item .\.env.example .\.env -Force
```

But: créer `.env` local pour les variables infra.

## 3) Vérifier la présence des variables clés

```powershell
Get-Content .\.env
```

But: contrôler `GCP_PROJECT_ID`, `TF_VAR_project_id`, `TF_VAR_*_service_account_email`.

## B) Cloud Shell GCP

## 1) Cibler le projet

```bash
gcloud auth login
gcloud config set project cartographie-data-engineer
```

But: toutes les commandes suivantes ciblent le bon projet.

## 2) Créer les service accounts applicatifs

```bash
gcloud iam service-accounts create ingestion-sa --display-name="Ingestion SA"
gcloud iam service-accounts create dbt-sa --display-name="DBT SA"
gcloud iam service-accounts create dashboard-sa --display-name="Dashboard SA"
```

But: comptes techniques dédiés par usage (ingestion / dbt / dashboard).

## 3) Créer le service account de déploiement Terraform

```bash
gcloud iam service-accounts create terraform-deployer-sa --display-name="Terraform Deployer SA"
```

But: compte dédié au provisioning infra.

## 4) Assigner les rôles minimum (INFRA-01/02/03)

```bash
gcloud projects add-iam-policy-binding cartographie-data-engineer \
  --member="serviceAccount:terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding cartographie-data-engineer \
  --member="serviceAccount:terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin"
```

But: autoriser la création bucket + datasets BigQuery.

## 5) Récupérer les emails SA pour `.env`

```bash
gcloud iam service-accounts list --format="table(email,displayName)"
```

But: remplir les variables `TF_VAR_ingestion_service_account_email`, `TF_VAR_dbt_service_account_email`, `TF_VAR_dashboard_service_account_email`.

## 6) Vérifier les ressources créées

```bash
gcloud storage buckets list --project cartographie-data-engineer
bq ls --project_id=cartographie-data-engineer
```

But: valider la création effective des éléments GCP.

## Notes importantes

- Si `gcloud` n'est pas installé localement, utiliser Cloud Shell pour les commandes manuelles GCP.
- Si l'organisation bloque les clés SA (`iam.disableServiceAccountKeyCreation`), utiliser `gcloud auth application-default login` dans le conteneur `infra-iac` au lieu d'une clé JSON.
