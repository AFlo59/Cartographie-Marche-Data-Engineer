# Guide pas à pas — Workload Identity Federation GitHub ↔ GCP

Ce guide explique comment configurer **Workload Identity Federation (WIF)** pour permettre à GitHub Actions de déployer l’infrastructure GCP **sans clé JSON**.

Le but est de permettre au workflow GitHub Actions d’utiliser le service account `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com` pour exécuter Terraform via le conteneur `infra-iac`.

> Ce guide décrit le **chemin principal de release et de déploiement de l'infrastructure Terraform** dans le périmètre actuel.
> Les guides Docker et terminal local servent surtout au développement, à la validation manuelle et au debug avant PR.

---

## 1) Pourquoi utiliser WIF

WIF remplace le fichier `sa.json` par un mécanisme d’authentification courte durée :

- GitHub Actions émet un jeton OIDC temporaire
- GCP vérifie ce jeton via un provider OIDC GitHub
- GCP autorise ce jeton à **impersonate** le service account Terraform

Avantages :
- pas de clé JSON longue durée dans GitHub
- compatible avec les policies qui bloquent `iam.disableServiceAccountKeyCreation`
- meilleure sécurité pour INFRA-09

Note de périmètre : le workflow actuel couvre principalement `terraform plan` sur PR et `terraform apply` sur merge `main`. Les checks Python/dbt du backlog INFRA-09 restent à compléter séparément.

---

## 2) Pré-requis

- Projet GCP existant : `cartographie-data-engineer`
- Service account existant : `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com`
- Rôles du SA déjà en place pour le scope actuel :
  - `roles/storage.admin`
  - `roles/bigquery.admin`
- Accès admin suffisant sur le projet pour créer pool/provider IAM
- Repo GitHub cible :
  - Org : `GITHUB_ORG`
  - Repo : `GITHUB_REPO`

### 2.1) Donner les droits au service account utilisé par WIF

Le service account référencé dans `GCP_WIF_SERVICE_ACCOUNT` doit avoir les droits pour gérer les ressources Terraform.

Commandes (à exécuter une fois) :

```bash
TF_SA="terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"
INGESTION_SA="ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com"

# Ressources infra
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/bigquery.admin"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/cloudscheduler.admin"

gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/secretmanager.admin"

# Permet d'assigner ingestion-sa au Cloud Run Job
gcloud iam service-accounts add-iam-policy-binding ${INGESTION_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${PROJECT}
```

Optionnel (uniquement si Terraform doit gérer des bindings IAM au niveau projet, ex: `roles/bigquery.jobUser`) :

```bash
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/resourcemanager.projectIamAdmin"
```

Note : dans le workflow actuel, `TF_VAR_manage_project_job_user_bindings` est positionné à `false`, donc ce rôle optionnel n'est pas requis pour le flux CI standard.

Placeholders utilisés dans ce guide :

- `PROJECT_NUMBER` = identifiant numérique du projet GCP.
- `GITHUB_ORG` = organisation ou utilisateur propriétaire du repo GitHub.
- `GITHUB_REPO` = nom du repository GitHub.
- `terraform-deployer-sa@...` = service account réellement utilisé par la CI pour exécuter Terraform.

---

## 3) Récupérer le project number

```bash
gcloud projects describe cartographie-data-engineer --format="value(projectNumber)"
```

Noter la valeur retournée — elle sera utilisée dans toutes les commandes suivantes.

---

## 4) Activer les APIs nécessaires

```bash
gcloud services enable iamcredentials.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com --project cartographie-data-engineer
```

Pourquoi :
- `iamcredentials.googleapis.com` permet l’impersonation du service account
- `iam.googleapis.com` couvre la partie IAM/WIF

---

## 5) Créer le Workload Identity Pool

```bash
gcloud iam workload-identity-pools create github-pool \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --description="Pool OIDC pour GitHub Actions" \
  --project="cartographie-data-engineer"
```

Vérification :

```bash
gcloud iam workload-identity-pools list --location="global" --project="cartographie-data-engineer"
```

---

## 6) Créer le Provider OIDC GitHub

> GCP exige un `--attribute-condition` pour restreindre qui peut s'authentifier via ce provider. Sans lui, la commande échoue avec `INVALID_ARGUMENT`.

```bash
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
  --attribute-condition="attribute.repository_owner == 'GITHUB_ORG'" \
  --project="cartographie-data-engineer"
```

Vérification :

```bash
gcloud iam workload-identity-pools providers list \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --project="cartographie-data-engineer"
```

---

## 7) Autoriser le repo GitHub à utiliser `terraform-deployer-sa`

```bash
gcloud iam service-accounts add-iam-policy-binding terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com \
  --project="cartographie-data-engineer" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe cartographie-data-engineer --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/GITHUB_ORG/GITHUB_REPO"
```

> La sous-commande `$(gcloud projects describe ...)` récupère le project number automatiquement — pas besoin de le connaître par cœur.

Exemple de logique :
- seul ce repo GitHub pourra utiliser le SA Terraform
- pas besoin de stocker de clé JSON dans GitHub

---

## 8) Récupérer le nom complet du provider

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --project="cartographie-data-engineer" \
  --format="value(name)"
```

Résultat attendu (forme) :

```text
projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider
```

Conserver cette valeur pour GitHub.

---

## 9) Configurer GitHub

Dans le repository GitHub, ajouter :

### Variables / secrets GitHub

- `GCP_PROJECT_ID` = `cartographie-data-engineer`
- `GCP_WIF_PROVIDER` = valeur retournée à l'étape 8 (forme : `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider`)
- `GCP_WIF_SERVICE_ACCOUNT` = `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com`

> Ces 3 valeurs vont dans **GitHub → Settings → Secrets and variables → Actions**, pas dans `.env` ni `docker-compose.yml`.
> WIF est uniquement utilisé par le workflow CI, pas par le container Docker local.

Avec WIF, **pas besoin** de `GCP_SA_KEY`.

---

## 10) Permissions minimales dans le workflow GitHub Actions

Le workflow devra contenir :

```yaml
permissions:
  contents: read
  id-token: write
```

Pourquoi :
- `id-token: write` permet à GitHub d’émettre le jeton OIDC
- `contents: read` permet le checkout du repo

---

## 11) Comment le workflow s’authentifie ensuite

Le workflow fera :

1. Checkout du repo
2. Auth GitHub → GCP via WIF
3. Lancement du conteneur `infra-iac`
4. Exécution de `terraform init`, `validate`, `plan`, `apply`

Le conteneur Terraform ne porte pas de clé JSON persistante.

Dans le périmètre actuel, cette chaîne correspond à la release infra. Elle ne couvre pas encore l'ensemble du pipeline qualité/dbt décrit par le backlog INFRA-09.

---

## 12) Vérifications de fin

### Vérifier le pool

```bash
gcloud iam workload-identity-pools describe github-pool --location=global --project=cartographie-data-engineer
```

### Vérifier le provider

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --project=cartographie-data-engineer
```

### Vérifier le binding sur le service account

```bash
gcloud iam service-accounts get-iam-policy terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com \
  --project=cartographie-data-engineer
```

Attendu : une entrée `roles/iam.workloadIdentityUser` pointant vers `principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/attribute.repository/GITHUB_ORG/GITHUB_REPO`.

---

## 13) Dépannage rapide

### Erreur `PERMISSION_DENIED` lors de la création du pool/provider
Il manque des droits IAM projet/org pour gérer WIF.

### Le workflow GitHub n’arrive pas à s’authentifier
Vérifier :
- `id-token: write` dans le workflow
- `GCP_WIF_PROVIDER` correct
- `GCP_WIF_SERVICE_ACCOUNT` correct
- binding `roles/iam.workloadIdentityUser` avec `GITHUB_ORG/GITHUB_REPO`

### Le repo GitHub doit être restreint à une branche
Vous pouvez raffiner ensuite avec un provider conditionné sur `attribute.ref` (ex: `refs/heads/main`).
Pour l’instant, garder simple pour le projet.

---

## 14) Recommandation pour ce projet

Vu votre contexte actuel :

- **local** → continuer avec `terraform-oauth`
- **CI GitHub** → utiliser **WIF** pour la release infra Terraform
- **runtime ingestion/dbt/dashboard** → IAM + Secret Manager

C’est la combinaison la plus simple et la plus saine pour le périmètre actuel.

---

## 15) Références

- Orchestration globale : [docs/cicd/deployment_orchestration.md](docs/cicd/deployment_orchestration.md)
- Setup GCP manuel : [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md)
- Commandes Docker infra : [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md)
- Backlog projet : [objectif/backlog_agile_datatalent.md](objectif/backlog_agile_datatalent.md)
