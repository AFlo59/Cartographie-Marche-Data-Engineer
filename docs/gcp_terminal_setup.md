# Setup GCP (Cloud Shell) — guide rapide

Ce guide regroupe les commandes utilisées pour initialiser l'environnement GCP du projet et récupérer les infos à mettre dans `.env`.

## 1) Sélectionner le projet

```bash
gcloud config set project cartographie-data-engineer
```

Pourquoi : fixe le projet actif pour toutes les commandes suivantes.

## 2) Vérifier le parent du projet (organisation/folder)

```bash
gcloud projects describe cartographie-data-engineer --format="value(parent.type,parent.id)"
```

Pourquoi : utile pour comprendre les politiques d'organisation (tags, IAM, contraintes).

## 3) (Optionnel) Vérifier les tags d'environnement

```bash
gcloud resource-manager tags keys list --parent=organizations/ORG_ID --format="table(name,shortName)"
```

```bash
gcloud resource-manager tags values list --parent=tagKeys/TAG_KEY_ID --format="table(name,shortName)"
```

```bash
gcloud resource-manager tags bindings create --parent=//cloudresourcemanager.googleapis.com/projects/cartographie-data-engineer --tag-value=tagValues/TAG_VALUE_ID
```

Pourquoi : certaines organisations imposent un tag `environment` (Development/Test/Staging/Production).

Note : une erreur `PERMISSION_DENIED` sur `tagKeys.list` signifie que le compte n'a pas les droits org nécessaires. Il faut passer par un admin org.

## 4) Créer les 3 Service Accounts

```bash
gcloud iam service-accounts create ingestion-sa --display-name="Ingestion SA"
gcloud iam service-accounts create dbt-sa --display-name="DBT SA"
gcloud iam service-accounts create dashboard-sa --display-name="Dashboard SA"
```

Pourquoi : ces comptes sont utilisés par ingestion, dbt et dashboard avec des permissions séparées.

## 5) Récupérer les emails des Service Accounts

```bash
gcloud iam service-accounts list --format="table(email,displayName)"
```

Pourquoi : ces emails doivent être copiés dans `.env`.

## 6) Valeurs à remplir dans `.env`

```dotenv
TF_VAR_ingestion_service_account_email=ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com
TF_VAR_dbt_service_account_email=dbt-sa@cartographie-data-engineer.iam.gserviceaccount.com
TF_VAR_dashboard_service_account_email=dashboard-sa@cartographie-data-engineer.iam.gserviceaccount.com
```

## 7) APIs GCP à activer (minimum)

```bash
gcloud services enable storage.googleapis.com bigquery.googleapis.com run.googleapis.com cloudscheduler.googleapis.com secretmanager.googleapis.com --project cartographie-data-engineer
```

Pourquoi : prépare les services nécessaires aux tickets INFRA-02 à INFRA-06.

## 8) Créer un compte de déploiement Terraform (recommandé)

```bash
gcloud iam service-accounts create terraform-deployer-sa --display-name="Terraform Deployer SA"
```

Donner les rôles minimaux pour INFRA-01/02/03 :

```bash
gcloud projects add-iam-policy-binding cartographie-data-engineer \
  --member="serviceAccount:terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding cartographie-data-engineer \
  --member="serviceAccount:terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin"
```

Créer une clé JSON locale (à faire depuis un poste local avec gcloud, pas dans le repo) :

```bash
gcloud iam service-accounts keys create ./secrets/gcp-sa.json \
  --iam-account=terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com
```

Pourquoi : le conteneur Docker Terraform lit cette clé via `/workspace/secrets/gcp-sa.json`.

## 9) Vérification rapide

```bash
gcloud config get-value project
gcloud iam service-accounts list --format="value(email)"
```

Résultat attendu : projet actif correct + 3 emails SA visibles.
