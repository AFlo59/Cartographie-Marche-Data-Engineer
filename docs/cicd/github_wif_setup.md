# Guide pas à pas — Workload Identity Federation GitHub → GCP

Ce guide explique comment configurer **Workload Identity Federation (WIF)** pour permettre à GitHub Actions de déployer l'infrastructure GCP **sans clé JSON**.

Le but est de permettre au workflow GitHub Actions d'utiliser le service account `terraform-deployer-sa@${PROJECT_ID}.iam.gserviceaccount.com` pour exécuter Terraform via le conteneur `infra-iac`.

> Ce guide décrit le **chemin principal de release et de déploiement de l'infrastructure Terraform** dans le périmètre actuel.
> Les guides Docker et terminal local servent surtout au développement, à la validation manuelle et au debug avant PR.

---

## Variables de configuration

Définir ces variables **une seule fois** dans votre terminal Cloud Shell avant d'exécuter les commandes de ce guide :

```bash
# ═══════════════════════════════════════════════════════════════
# Variables — adapter à votre projet avant d'exécuter ce guide
# ═══════════════════════════════════════════════════════════════
PROJECT_ID="votre-projet-gcp"              # ← ID de votre projet GCP
REGION="europe-west1"                       # ← région GCP
GITHUB_ORG="votre-org-ou-username"         # ← organisation ou username GitHub
GITHUB_REPO="votre-repo"                   # ← nom du repository GitHub

# Comptes de service (construits automatiquement)
TF_SA="terraform-deployer-sa@${PROJECT_ID}.iam.gserviceaccount.com"
INGESTION_SA="ingestion-sa@${PROJECT_ID}.iam.gserviceaccount.com"
DBT_SA="dbt-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

Toutes les commandes de ce guide utilisent ces variables — il suffit de les changer ici pour adapter le guide à un autre projet.

---

## Variables a definir

Definir ces variables en debut de session Cloud Shell avant d'executer les commandes de ce guide :

```bash
GCP_PROJECT_ID="your-gcp-project-id"   # identifiant de votre projet GCP  <- a renseigner
GITHUB_ORG="your-github-org"            # organisation ou utilisateur GitHub <- a renseigner
GITHUB_REPO="your-github-repo"          # nom du repo GitHub                 <- a renseigner

# Service accounts (construits a partir de GCP_PROJECT_ID)
TF_SA="terraform-deployer-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
INGESTION_SA="ingestion-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
DBT_SA="dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
```

## 1) Pourquoi utiliser WIF

WIF remplace le fichier `sa.json` par un mécanisme d'authentification courte durée :

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

- Projet GCP existant (valeur de `PROJECT_ID` ci-dessus)
- Service account `terraform-deployer-sa` déjà créé
- Rôles du SA déjà en place pour le scope actuel :
  - `roles/storage.admin`
  - `roles/bigquery.admin`
  - `roles/artifactregistry.admin` (requis pour créer ET modifier le repo AR — manquant = erreur 403)
- Accès admin suffisant sur le projet pour créer pool/provider IAM
- Repo GitHub cible : `${GITHUB_ORG}/${GITHUB_REPO}`

### 2.0) Ordre recommandé avant le premier `terraform apply` depuis GitHub Actions

Avant de configurer ou tester le workflow CI, suivre cet ordre :

1. Activer une fois les APIs GCP requises sur le projet.
2. Donner au service account WIF les rôles Terraform du périmètre infra.
3. Configurer WIF GitHub → GCP.
4. Lancer un `plan` en PR puis un `apply` sur `main`.

Si l'étape 1 n'est pas faite, le workflow peut échouer avant `terraform apply` avec `Required API is disabled`.

Commandes one-shot recommandées :

```bash
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project=${PROJECT_ID}
```

Référence principale pour le socle projet : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md).

### 2.1) Donner les droits au service account utilisé par WIF

Le service account référencé dans `GCP_WIF_SERVICE_ACCOUNT` doit avoir les droits pour gérer les ressources Terraform.

Commandes (à exécuter une fois) :

```bash
# Ressources infra de base
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/bigquery.admin"

# ❌ REQUIS — sans ce rôle, terraform apply échoue avec 403 sur le repo AR
# (update de la description du repo Artifact Registry)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/artifactregistry.admin"

# À accorder avant d'activer create_compute_job=true (INFRA-04/05)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/cloudscheduler.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/secretmanager.admin"

# Permet d'assigner ingestion-sa et dbt-sa aux Cloud Run Jobs
gcloud iam service-accounts add-iam-policy-binding ${INGESTION_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${PROJECT_ID}

gcloud iam service-accounts add-iam-policy-binding ${DBT_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${PROJECT_ID}
```

Optionnel (uniquement si Terraform doit gérer des bindings IAM au niveau projet, ex: `roles/bigquery.jobUser`) :

```bash
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/resourcemanager.projectIamAdmin"
```

Optionnel (si vous voulez que la CI puisse activer automatiquement des APIs GCP manquantes) :

```bash
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/serviceusage.serviceUsageAdmin"
```

Sinon, activer manuellement une fois les APIs requises :

```bash
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  --project=${PROJECT_ID}
```

Le workflow `infra-deploy.yml` vérifie explicitement ces 5 APIs avant l'`apply` sur `main`.

Note : dans le workflow actuel, `TF_VAR_manage_project_job_user_bindings` est positionné à `false`, donc le rôle `projectIamAdmin` n'est pas requis pour le flux CI standard.

---

## 3) Récupérer le project number

```bash
gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)"
```

Noter la valeur retournée — elle sera utilisée dans la commande de la section 7.

---

## 4) Activer les APIs nécessaires

```bash
gcloud services enable \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project ${PROJECT_ID}
```

Pourquoi :

- `iamcredentials.googleapis.com` permet l'impersonation du service account
- `iam.googleapis.com` couvre la partie IAM/WIF

---

## 5) Créer le Workload Identity Pool

```bash
gcloud iam workload-identity-pools create github-pool \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --description="Pool OIDC pour GitHub Actions" \
  --project="${PROJECT_ID}"
```

Vérification :

```bash
gcloud iam workload-identity-pools list \
  --location="global" \
  --project="${PROJECT_ID}"
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
  --attribute-condition="attribute.repository_owner == '${GITHUB_ORG}'" \
  --project="${PROJECT_ID}"
```

Vérification :

```bash
gcloud iam workload-identity-pools providers list \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --project="${PROJECT_ID}"
```

---

## 7) Autoriser le repo GitHub à utiliser `terraform-deployer-sa`

```bash
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')

gcloud iam service-accounts add-iam-policy-binding ${TF_SA} \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"
```

> `PROJECT_NUMBER` est récupéré automatiquement — pas besoin de le connaître par cœur.

Logique :

- seul ce repo GitHub pourra utiliser le SA Terraform
- pas besoin de stocker de clé JSON dans GitHub

---

## 8) Récupérer le nom complet du provider

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --project="${PROJECT_ID}" \
  --format="value(name)"
```

Résultat attendu (forme) :

```text
projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider
```

Conserver cette valeur pour la configuration GitHub (section 9).

---

## 9) Configurer GitHub

Dans le repository GitHub, ajouter dans **GitHub → Settings → Secrets and variables → Actions** :

| Nom | Valeur |
| --- | ------ |
| `GCP_PROJECT_ID` | valeur de `PROJECT_ID` |
| `GCP_WIF_PROVIDER` | valeur retournée à l'étape 8 |
| `GCP_WIF_SERVICE_ACCOUNT` | valeur de `TF_SA` |

> Ces 3 valeurs vont dans les **Secrets ou Variables GitHub Actions**, pas dans `.env` ni `docker-compose.yml`.
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

- `id-token: write` permet à GitHub d'émettre le jeton OIDC
- `contents: read` permet le checkout du repo

---

## 11) Comment le workflow s'authentifie ensuite

Le workflow `infra-deploy.yml` orchestre 4 jobs sur push `main` :

1. **`ingestion-verify`** — Checkout + `docker build` Dockerfile ingestion (vérifie la validité)
2. **`dbt-verify`** — Checkout + Auth WIF + `docker build` dbt + `dbt parse` + `dbt compile`
3. **`terraform`** (bloqué jusqu'au succès des 2 verify) — Auth WIF + `terraform init/validate/apply`
4. **`push-images`** (bloqué jusqu'au succès de terraform) — Auth WIF + `docker build` + `docker push` ingestion et dbt vers Artifact Registry

Le conteneur Terraform ne porte pas de clé JSON persistante.

Sur PR : seuls `ingestion-verify` + `dbt-verify` + `terraform plan` s'exécutent. Pas de push images, pas d'apply.

---

## 12) Vérifications de fin

### Vérifier le pool

```bash
gcloud iam workload-identity-pools describe github-pool \
  --location=global \
  --project=${PROJECT_ID}
```

### Vérifier le provider

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --project=${PROJECT_ID}
```

### Vérifier le binding sur le service account

```bash
gcloud iam service-accounts get-iam-policy ${TF_SA} \
  --project=${PROJECT_ID}
```

Attendu : une entrée `roles/iam.workloadIdentityUser` pointant vers `principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}`.

---

## 13) Dépannage rapide

### Erreur `PERMISSION_DENIED` lors de la création du pool/provider

Il manque des droits IAM projet/org pour gérer WIF.

### Le workflow GitHub n'arrive pas à s'authentifier

Vérifier :

- `id-token: write` dans le workflow
- `GCP_WIF_PROVIDER` correct (valeur de l'étape 8)
- `GCP_WIF_SERVICE_ACCOUNT` correct (valeur de `TF_SA`)
- binding `roles/iam.workloadIdentityUser` avec `${GITHUB_ORG}/${GITHUB_REPO}`

### Le repo GitHub doit être restreint à une branche

Vous pouvez raffiner ensuite avec un provider conditionné sur `attribute.ref` (ex: `refs/heads/main`).
Pour l'instant, garder simple pour le projet.

---

## 14) Recommandation pour ce projet

- **local** → continuer avec `terraform-oauth`
- **CI GitHub** → utiliser **WIF** pour la release infra Terraform
- **runtime ingestion/dbt/dashboard** → IAM + Secret Manager

C'est la combinaison la plus simple et la plus saine pour le périmètre actuel.

---

## 15) Références

- Orchestration globale : [docs/cicd/deployment_orchestration.md](../cicd/deployment_orchestration.md)
- Setup GCP manuel : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- Commandes Docker infra : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- Backlog projet : [objectif/backlog_agile_datatalent.md](../../objectif/backlog_agile_datatalent.md)
