# Guide pas  pas  Workload Identity Federation GitHub ? GCP

Ce guide explique comment configurer **Workload Identity Federation (WIF)** pour permettre  GitHub Actions de dployer linfrastructure GCP **sans cl JSON**.

Le but est de permettre au workflow GitHub Actions dutiliser le service account `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com` pour excuter Terraform via le conteneur `infra-iac`.

> Ce guide dcrit le **chemin principal de release et de dploiement de l'infrastructure Terraform** dans le primtre actuel.
> Les guides Docker et terminal local servent surtout au dveloppement,  la validation manuelle et au debug avant PR.

---

## 1) Pourquoi utiliser WIF

WIF remplace le fichier `sa.json` par un mcanisme dauthentification courte dure :

- GitHub Actions met un jeton OIDC temporaire
- GCP vrifie ce jeton via un provider OIDC GitHub
- GCP autorise ce jeton  **impersonate** le service account Terraform

Avantages :
- pas de cl JSON longue dure dans GitHub
- compatible avec les policies qui bloquent `iam.disableServiceAccountKeyCreation`
- meilleure scurit pour INFRA-09

Note de primtre : le workflow actuel couvre principalement `terraform plan` sur PR et `terraform apply` sur merge `main`. Les checks Python/dbt du backlog INFRA-09 restent  complter sparment.

---

## 2) Pr-requis

- Projet GCP existant : `cartographie-data-engineer`
- Service account existant : `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com`
- Rles du SA dj en place pour le scope actuel :
  - `roles/storage.admin`
  - `roles/bigquery.admin`
- Accs admin suffisant sur le projet pour crer pool/provider IAM
- Repo GitHub cible :
  - Org : `GITHUB_ORG`
  - Repo : `GITHUB_REPO`

### 2.0) Ordre recommand avant le premier `terraform apply` depuis GitHub Actions

Avant de configurer ou tester le workflow CI, suivre cet ordre :

1. Activer une fois les APIs GCP requises sur le projet.
2. Donner au service account WIF les rles Terraform du primtre infra.
3. Configurer WIF GitHub ? GCP.
4. Lancer un `plan` en PR puis un `apply` sur `main`.

Si l'tape 1 n'est pas faite, le workflow peut chouer avant `terraform apply` avec `Required API is disabled`.

Commandes one-shot recommandes :

```bash
PROJECT="cartographie-data-engineer"

gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project=${PROJECT}
```

Rfrence principale pour le socle projet : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md).

### 2.1) Donner les droits au service account utilis par WIF

Le service account rfrenc dans `GCP_WIF_SERVICE_ACCOUNT` doit avoir les droits pour grer les ressources Terraform.

Commandes ( excuter une fois) :

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

Optionnel (uniquement si Terraform doit grer des bindings IAM au niveau projet, ex: `roles/bigquery.jobUser`) :

```bash
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/resourcemanager.projectIamAdmin"
```

Optionnel (si vous voulez que la CI puisse activer automatiquement des APIs GCP manquantes) :

```bash
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/serviceusage.serviceUsageAdmin"
```

Sinon, activer manuellement une fois les APIs requises :

```bash
gcloud services enable storage.googleapis.com bigquery.googleapis.com run.googleapis.com cloudscheduler.googleapis.com secretmanager.googleapis.com \
  --project=${PROJECT}
```

Le workflow `infra-deploy.yml` vrifie explicitement ces 5 APIs avant l'`apply` sur `main`.

Note : dans le workflow actuel, `TF_VAR_manage_project_job_user_bindings` est positionn  `false`, donc ce rle optionnel n'est pas requis pour le flux CI standard.

Placeholders utiliss dans ce guide :

- `PROJECT_NUMBER` = identifiant numrique du projet GCP.
- `GITHUB_ORG` = organisation ou utilisateur propritaire du repo GitHub.
- `GITHUB_REPO` = nom du repository GitHub.
- `terraform-deployer-sa@...` = service account rellement utilis par la CI pour excuter Terraform.

---

## 3) Rcuprer le project number

```bash
gcloud projects describe cartographie-data-engineer --format="value(projectNumber)"
```

Noter la valeur retourne  elle sera utilise dans toutes les commandes suivantes.

---

## 4) Activer les APIs ncessaires

```bash
gcloud services enable iamcredentials.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com --project cartographie-data-engineer
```

Pourquoi :
- `iamcredentials.googleapis.com` permet limpersonation du service account
- `iam.googleapis.com` couvre la partie IAM/WIF

---

## 5) Crer le Workload Identity Pool

```bash
gcloud iam workload-identity-pools create github-pool \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --description="Pool OIDC pour GitHub Actions" \
  --project="cartographie-data-engineer"
```

Vrification :

```bash
gcloud iam workload-identity-pools list --location="global" --project="cartographie-data-engineer"
```

---

## 6) Crer le Provider OIDC GitHub

> GCP exige un `--attribute-condition` pour restreindre qui peut s'authentifier via ce provider. Sans lui, la commande choue avec `INVALID_ARGUMENT`.

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

Vrification :

```bash
gcloud iam workload-identity-pools providers list \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --project="cartographie-data-engineer"
```

---

## 7) Autoriser le repo GitHub  utiliser `terraform-deployer-sa`

```bash
gcloud iam service-accounts add-iam-policy-binding terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com \
  --project="cartographie-data-engineer" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe cartographie-data-engineer --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/GITHUB_ORG/GITHUB_REPO"
```

> La sous-commande `$(gcloud projects describe ...)` rcupre le project number automatiquement  pas besoin de le connatre par cur.

Exemple de logique :
- seul ce repo GitHub pourra utiliser le SA Terraform
- pas besoin de stocker de cl JSON dans GitHub

---

## 8) Rcuprer le nom complet du provider

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --project="cartographie-data-engineer" \
  --format="value(name)"
```

Rsultat attendu (forme) :

```text
projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider
```

Conserver cette valeur pour GitHub.

---

## 9) Configurer GitHub

Dans le repository GitHub, ajouter :

### Variables / secrets GitHub

- `GCP_PROJECT_ID` = `cartographie-data-engineer`
- `GCP_WIF_PROVIDER` = valeur retourne  l'tape 8 (forme : `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider`)
- `GCP_WIF_SERVICE_ACCOUNT` = `terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com`

> Ces 3 valeurs vont dans **GitHub ? Settings ? Secrets and variables ? Actions**, pas dans `.env` ni `docker-compose.yml`.
> WIF est uniquement utilis par le workflow CI, pas par le container Docker local.

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
- `id-token: write` permet  GitHub dmettre le jeton OIDC
- `contents: read` permet le checkout du repo

---

## 11) Comment le workflow sauthentifie ensuite

Le workflow fera :

1. Checkout du repo
2. Auth GitHub ? GCP via WIF
3. Lancement du conteneur `infra-iac`
4. Excution de `terraform init`, `validate`, `plan`, `apply`

Le conteneur Terraform ne porte pas de cl JSON persistante.

Dans le primtre actuel, cette chane correspond  la release infra. Elle ne couvre pas encore l'ensemble du pipeline qualit/dbt dcrit par le backlog INFRA-09.

---

## 12) Vrifications de fin

### Vrifier le pool

```bash
gcloud iam workload-identity-pools describe github-pool --location=global --project=cartographie-data-engineer
```

### Vrifier le provider

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --project=cartographie-data-engineer
```

### Vrifier le binding sur le service account

```bash
gcloud iam service-accounts get-iam-policy terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com \
  --project=cartographie-data-engineer
```

Attendu : une entre `roles/iam.workloadIdentityUser` pointant vers `principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/attribute.repository/GITHUB_ORG/GITHUB_REPO`.

---

## 13) Dpannage rapide

### Erreur `PERMISSION_DENIED` lors de la cration du pool/provider
Il manque des droits IAM projet/org pour grer WIF.

### Le workflow GitHub narrive pas  sauthentifier
Vrifier :
- `id-token: write` dans le workflow
- `GCP_WIF_PROVIDER` correct
- `GCP_WIF_SERVICE_ACCOUNT` correct
- binding `roles/iam.workloadIdentityUser` avec `GITHUB_ORG/GITHUB_REPO`

### Le repo GitHub doit tre restreint  une branche
Vous pouvez raffiner ensuite avec un provider conditionn sur `attribute.ref` (ex: `refs/heads/main`).
Pour linstant, garder simple pour le projet.

---

## 14) Recommandation pour ce projet

Vu votre contexte actuel :

- **local** ? continuer avec `terraform-oauth`
- **CI GitHub** ? utiliser **WIF** pour la release infra Terraform
- **runtime ingestion/dbt/dashboard** ? IAM + Secret Manager

Cest la combinaison la plus simple et la plus saine pour le primtre actuel.

---

## 15) Rfrences

- Orchestration globale : [docs/cicd/deployment_orchestration.md](../cicd/deployment_orchestration.md)
- Setup GCP manuel : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- Commandes Docker infra : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- Backlog projet : [objectif/backlog_agile_datatalent.md](../../objectif/backlog_agile_datatalent.md)
