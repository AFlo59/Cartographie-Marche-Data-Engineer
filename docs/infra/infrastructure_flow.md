# 🏗️ Flux Infrastructure & Terraform

## 📋 Vue d'ensemble

Ce document explique comment les données circulent dans notre pipeline d'infrastructure, de GitHub Actions jusqu'à GCP.

### Décision actuelle ingestion

- 1 Cloud Run Job: `datatalent-ingestion-job`
- 3 Cloud Scheduler jobs: `france_travail`, `sirene`, `geo`
- chaque Scheduler déclenche le même job avec `INGESTION_SOURCE=<source>` (override env)

Ce modèle est actuellement le plus simple et le moins coûteux en exploitation pour votre fréquence (hebdo/mensuel).

---

## 1️⃣ Sources des données

### **GitHub Secrets** (Conteneur sécurisé)
Définis dans: `GitHub > Settings > Secrets and variables > Actions`

```
GCP_PROJECT_ID              = "${GCP_PROJECT_ID}"  # Ex: my-gcp-project
GCP_WIF_PROVIDER            = "projects/XXX/locations/global/workloadIdentityPools/XXX"
GCP_WIF_SERVICE_ACCOUNT     = "${TERRAFORM_SA_EMAIL}"  # Ex: terraform-deployer@my-gcp-project.iam.gserviceaccount.com
```

**Pourquoi ces secrets?**
- `GCP_PROJECT_ID`: Identifie le projet GCP cible
- `GCP_WIF_PROVIDER`: Pool d'identités pour l'authentification fédérée GitHub ↔ GCP
- `GCP_WIF_SERVICE_ACCOUNT`: Compte service qui applique les changements Terraform

---

### **Env vars du Workflow** (Défini dans `.github/workflows/infra-deploy.yml`)

Ces variables sont **codées en dur** dans le workflow pour contrôler la configuration:

```yaml
env:
  # Projet GCP
  TF_VAR_project_id: ${{ secrets.GCP_PROJECT_ID }}
  TF_VAR_region: europe-west1
  TF_VAR_location: EU
  TF_VAR_environment: dev

  # Bucket de données brutes
  TF_VAR_bucket_versioning_enabled: "true"
  TF_VAR_bucket_force_destroy: "false"

  # BigQuery datasets
  TF_VAR_raw_dataset_id: raw
  TF_VAR_staging_dataset_id: staging
  TF_VAR_marts_dataset_id: marts

  # Service Accounts
  TF_VAR_ingestion_service_account_email: ${INGESTION_SA_EMAIL}
  TF_VAR_dbt_service_account_email: ${DBT_SA_EMAIL}
  TF_VAR_dashboard_service_account_email: ${DASHBOARD_SA_EMAIL}

  # Cloud Run Job (Ingestion)
  TF_VAR_compute_image: ${DOCKER_IMAGE_URL}
  TF_VAR_compute_memory: 512Mi
  TF_VAR_compute_cpu: "1"

  # Backend Terraform (stockage du state)
  TF_BACKEND_BUCKET: ${TERRAFORM_STATE_BUCKET}
```

**Préfixe `TF_VAR_`**: Terraform récupère automatiquement toutes les env vars commençant par `TF_VAR_` et les utilise comme valeurs de variables! 

---

## 2️⃣ Flux d'exécution CI/CD

### **Phase 1: Authentification**

```
GitHub Actions Secret
    ↓
google-github-actions/auth@v3
    ↓
WIF (Workload Identity Federation)
    ↓
Service Account: terraform-deployer-sa
    ↓
Token GCP temporaire (validité: 1h)
```

Le workflow échange le JWT GitHub contre un token GCP en utilisant la pool d'identités fédérée.

### **Phase 2: Terraform Init**

```
1. terraform init
   ├─ Lit TF_BACKEND_BUCKET (défini dans env)
   ├─ Authentifie auprès de GCS (via WIF token)
   └─ Télécharge terraform.tfstate depuis le bucket
```

**Qu'est-ce qui est téléchargé?**

Le fichier `terraform.tfstate` en JSON contient l'état RÉEL des ressources:

```json
{
  "version": 4,
  "terraform_version": "1.9.8",
  "resources": [
    {
      "type": "google_cloud_run_job",
      "name": "ingestion_job",
      "instances": [
        {
          "id": "${COMPUTE_JOB_NAME}",
          "attributes": {
            "image": "${DOCKER_IMAGE_URL}",
            "memory": "512Mi",
            "cpu": "1",
            "location": "europe-west1"
          }
        }
      ]
    }
  ]
}
```

### **Phase 3: Terraform Plan**

```
terraform plan
    ├─ Lit variables.tf (structure des inputs)
    ├─ Récupère TF_VAR_* depuis env
    ├─ Compare avec le state téléchargé depuis GCS
    ├─ Interroge GCP: "Ça existe vraiment?"
    └─ Génère un plan de changements
```

**Exemple de plan:**

```
Terraform will perform the following actions:

  # google_cloud_run_job.ingestion_job will be created
  + resource "google_cloud_run_job" "ingestion_job" {
      + id          = (known after apply)
      + image       = "${DOCKER_IMAGE_URL}"
      + memory      = "512Mi"
      + cpu         = "1"
      + location    = "europe-west1"
    }
```

### **Phase 4: Terraform Apply (main uniquement)**

```
terraform apply -auto-approve
    ├─ Crée/modifie les ressources dans GCP
    ├─ Récupère les IDs et attributs des ressources créées
    ├─ Met à jour le state local
    └─ SAUVEGARDE le state dans GCS
```

**Important**: Ce qui se passe:
1. Les ressources sont **créées/modifiées dans GCP** (pas local)
2. Terraform met à jour son fichier state **localement en mémoire**
3. Le state **est ensuite uploadé dans GCS** pour la prochaine exécution

---

## 3️⃣ Flux complet par branche

### **Cas 1: Pull Request sur develop ou main**

```
┌─────────────────────────────────────────────┐
│ PR créée (commit push sur feature/xxx)       │
└─────────────────────────────────────────────┘
                    ⬇️
┌─────────────────────────────────────────────┐
│ GitHub Actions déclenché (event: pull_request)
│                                              │
│ 1. Checkout du code                          │
│ 2. Vérifier secrets CI (fail-fast)          │
│ 3. Auth GCP via WIF                         │
│ 4. Setup gcloud CLI                         │
│ 5. Vérifier bucket d'état (❌ si missing)   │
│ 6. terraform init (télécharge state)        │
│ 7. terraform validate                       │
│ 8. terraform plan                           │
│ 9. Poster le plan en commentaire PR ✅      │
└─────────────────────────────────────────────┘
```

**Output dans la PR:**
```
## Terraform Plan

Terraform will perform the following actions:

  + resource "google_cloud_run_job" "ingestion_job" {
      + image = "europe-west1-docker.pkg.dev/.../ingestion:latest"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy
```

### **Cas 2: Push sur develop**

```
┌─────────────────────────────────────────────┐
│ Merge PR → push sur develop                  │
└─────────────────────────────────────────────┘
                    ⬇️
┌─────────────────────────────────────────────┐
│ GitHub Actions déclenché (event: push)      │
│                                              │
│ 1. Checkout du code                          │
│ 2. Vérifier secrets CI (fail-fast)          │
│ 3. Auth GCP via WIF                         │
│ 4. Setup gcloud CLI                         │
│ 5. Créer bucket d'état si absent ✅         │
│ 6. terraform init (télécharge state)        │
│ 7. terraform validate                       │
│ 8. ❌ PAS DE PLAN                            │
│ 9. ❌ PAS DE APPLY                           │
└─────────────────────────────────────────────┘

💡 Utilité: vérifier le wiring CI et la validité Terraform sans mutation infra.
```

### **Cas 3: Push sur main**

```
┌─────────────────────────────────────────────┐
│ Merge develop → push sur main                │
└─────────────────────────────────────────────┘
                    ⬇️
┌─────────────────────────────────────────────┐
│ GitHub Actions déclenché (event: push)      │
│                                              │
│ 1. Checkout du code                          │
│ 2. Vérifier secrets CI (fail-fast)          │
│ 3. Auth GCP via WIF                         │
│ 4. Setup gcloud CLI                         │
│ 5. Créer bucket d'état si absent ✅         │
│ 6. terraform init (télécharge state)        │
│ 7. terraform validate                        │
│ 8. Vérifier APIs requises                    │
│ 9. Import best-effort des ressources existantes│
│10. terraform apply -auto-approve 🚀          │
│    ├─ Crée/modifie ressources GCP            │
│    └─ Met à jour state dans GCS              │
└─────────────────────────────────────────────┘

🚨 IMPORTANT: Les changements sont appliqués immédiatement
```

---

## 4️⃣ Architecture des données

### **Diagramme complet**

```
┌──────────────────────────────────────────────────────────────────┐
│                      GITHUB                                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Secrets (chiffré):                                              │
│  ├─ GCP_PROJECT_ID                                              │
│  ├─ GCP_WIF_PROVIDER                                            │
│  └─ GCP_WIF_SERVICE_ACCOUNT                                     │
│                                                                  │
│  .github/workflows/infra-deploy.yml:                             │
│  ├─ Déclenche sur: PR vers main/develop, push sur main/develop │
│  └─ Env vars: TF_VAR_*, TF_BACKEND_BUCKET                       │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                            ⬇️
┌──────────────────────────────────────────────────────────────────┐
│                   GITHUB ACTIONS RUNNER                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  En mémoire (le temps du workflow):                              │
│  ├─ Code du repo (checkout)                                     │
│  ├─ Variables d'environnement TF_VAR_*                          │
│  ├─ Token GCP (via WIF)                                         │
│  ├─ terraform.tfstate (téléchargé depuis GCS)                  │
│  └─ tfplan file (résultat du plan)                             │
│                                                                  │
│  Terraform:                                                      │
│  └─ infra/                                                       │
│     ├─ variables.tf (structure des inputs)                      │
│     ├─ main.tf (logique des ressources)                         │
│     ├─ modules/ (composants réutilisables)                      │
│     └─ versions.tf (backend GCS, provider GCP)                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                            ⬇️
┌──────────────────────────────────────────────────────────────────┐
│                    GOOGLE CLOUD PLATFORM                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Authentification:                                               │
│  └─ Service Account: terraform-deployer-sa                      │
│     ├─ Rôle: storage.admin                                      │
│     ├─ Rôle: bigquery.admin                                     │
│     ├─ Rôle: run.admin                                          │
│     ├─ Rôle: cloudscheduler.admin                               │
│     └─ Rôle: secretmanager.admin                                │
│                                                                  │
│  Stockage d'état (Backend Terraform):                            │
│  └─ Bucket GCS: ${TERRAFORM_STATE_BUCKET}                      │
│     └─ Fichier: terraform.tfstate (JSON complet)               │
│        └─ Contient: État réel de TOUTES les ressources         │
│                                                                  │
│  Ressources créées par Terraform:                               │
│  ├─ Cloud Storage Bucket (raw data)                             │
│  ├─ BigQuery Datasets (raw, staging, marts)                     │
│  ├─ BigQuery Tables                                             │
  ├─ Cloud Run Job (ingestion) avec image Docker                 │
  ├─ Cloud Scheduler (triggers d'exécution)                      │
  ├─ Service Accounts (ingestion, transformation, dashboards)   │
│  └─ Secret Manager (FT_CLIENT_ID, etc.)                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5️⃣ Fichiers clés

### **`.github/workflows/infra-deploy.yml`**
- **Rôle**: Orchestrer le pipeline CI/CD
- **Déclenche sur**: PR/push sur main et develop
- **Actions**:
  - PR: terraform plan + commentaire
  - Push develop: terraform plan (validation)
  - Push main: terraform plan + apply

### **`infra/variables.tf`**
- **Rôle**: Définir la structure des inputs Terraform
- **Contient**: Variables avec defaults, validations, descriptions
- **Source des valeurs**: Env vars `TF_VAR_*` du workflow

### **`infra/main.tf`**
- **Rôle**: Logique principale, wiring des modules
- **Utilise**: Variables depuis `variables.tf`
- **Crée**: Toutes les ressources GCP

### **`infra/versions.tf`**
- **Rôle**: Configuration du backend GCS
- **Backend bucket**: `datatalent-tfstate-cartographie-data-engineer`
- **Path dans bucket**: `terraform.tfstate` (défaut)

### **`infra/terraform.tfvars`** ❌ **NE PAS COMMITER**
- **Rôle**: Override local des variables (développement)
- **Contient**: Valeurs spécifiques à l'environnement
- **Stratégie**: Laisser en `.gitignore`, copier depuis `terraform.tfvars.example`

---

## 6️⃣ Flux des secrets en détail

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Secret Storage (chiffré au repos)                    │
│                                                              │
│ secrets.GCP_PROJECT_ID                                      │
│ secrets.GCP_WIF_PROVIDER                                    │
│ secrets.GCP_WIF_SERVICE_ACCOUNT                             │
└─────────────────────────────────────────────────────────────┘
                          ⬇️ (lors du run)
┌─────────────────────────────────────────────────────────────┐
│ Runner - Step: "Check required CI secrets"                  │
│                                                              │
│ Décrypte les secrets en variables d'environnement           │
│ Vérifie qu'ils ne sont pas vides                            │
│ Fail-fast si absent (sortie du workflow)                    │
└─────────────────────────────────────────────────────────────┘
                          ⬇️
┌─────────────────────────────────────────────────────────────┐
│ Runner - Step: "Auth GCP via WIF"                           │
│                                                              │
│ google-github-actions/auth@v3 reçoit:                       │
│ ├─ workload_identity_provider (secret)                      │
│ └─ service_account (secret)                                 │
│                                                              │
│ Échange JWT GitHub → Token GCP                              │
│ Stocke le token dans GOOGLE_APPLICATION_CREDENTIALS         │
└─────────────────────────────────────────────────────────────┘
                          ⬇️
┌─────────────────────────────────────────────────────────────┐
│ Runner - Step: "Terraform Init/Plan/Apply"                 │
│                                                              │
│ Terraform utilise le token de GOOGLE_APPLICATION_CREDENTIALS
│ Pour accéder à GCS (bucket state) et GCP (ressources)       │
│                                                              │
│ gcloud CLI aussi utilise ce token                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 7️⃣ État Terraform (tfstate)

### **Backend Configuration: Source unique de vérité**

Le bucket du backend Terraform est **passé dynamiquement** via CLI pour éviter la duplication:

```bash
# Dans le workflow CI/CD:
terraform init -backend-config="bucket=${TF_BACKEND_BUCKET}"
```

**Pourquoi?**
- ✅ **Une seule source de vérité**: `TF_BACKEND_BUCKET` dans le workflow
- ✅ **Pas de drift**: Le workflow crée/vérifie le bucket, puis l'utilise
- ✅ **Flexibilité**: Facile de changer le bucket sans modifier le code Terraform

**Avant (❌ duplication):**
- `TF_BACKEND_BUCKET` défini dans le workflow
- `bucket = "..."` hardcodé dans `versions.tf`
- Risque: deux valeurs peuvent dériver

**Après (✅ dynamique):**
- `versions.tf` n'a que `prefix` (fixe)
- Bucket passé via `-backend-config=bucket=...`
- Une seule source de vérité

### **Qu'est-ce que le state?**

Le fichier `terraform.tfstate` est la **mémoire de Terraform**. Il stocke:

```json
{
  "version": 4,
  "terraform_version": "1.9.8",
  "serial": 42,
  "lineage": "abc123...",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "google_cloud_run_job",
      "name": "ingestion_job",
      "provider": "provider[\"registry.terraform.io/hashicorp/google\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "id": "${COMPUTE_JOB_NAME}",
            "location": "${REGION}",
            "name": "${COMPUTE_JOB_NAME}",
            "image": "${DOCKER_IMAGE_URL}",
            "memory": "512Mi",
            "cpu": "1",
            "environment_variables": {...}
          }
        }
      ]
    }
  ]
}
```

### **Pourquoi le state est stocké en GCS?**

1. **Persistance**: Survit au-delà du runner GitHub Actions
2. **Collaboration**: Tous les runs ultérieurs voient le même state
3. **Détection de drift**: Terraform sait ce qu'il a créé vs ce qui existe réellement
4. **Multi-environnement**: Différents state files pour dev/staging/prod (s'ils existaient)

### **Versioning du bucket**

Le bucket est configuré avec **versioning enabled**:

```bash
gcloud storage buckets update gs://${TERRAFORM_STATE_BUCKET} --versioning
```

Cela permet de:
- Récupérer les anciennes versions du state en cas de problème
- Auditer les changements (qui, quand, quoi)
- Rollback en cas de manipulation erronée

---

## 8️⃣ Sécurité

### **Protection des secrets**

✅ **Bonnes pratiques appliquées:**
- Secrets stockés chiffrés dans GitHub
- WIF: Pas de clés d'API en dur (échange de token)
- Service account restreint: Permissions IAM granulaires
- State file en GCS: Pas stocké localement dans git
- `.gitignore`: Exclut `*.tfvars` et `.terraform/`

### **Fichier terraform.tfvars**

❌ **À NE JAMAIS commiter:**
```hcl
project_id                           = "${GCP_PROJECT_ID}"
ingestion_service_account_email      = "${INGESTION_SA_EMAIL}"
dbt_service_account_email            = "${DBT_SA_EMAIL}"
dashboard_service_account_email      = "${DASHBOARD_SA_EMAIL}"
compute_image                        = "${DOCKER_IMAGE_URL}"
```

Ces valeurs **contiennent des identifiants de production** → reste local uniquement.

---

## 9️⃣ Troubleshooting

### **Problème: "Terraform backend bucket is missing"**

**Cause**: Le bucket `datatalent-tfstate-cartographie-data-engineer` n'existe pas

**Solution**:
```bash
# Depuis Cloud Shell ou gcloud CLI local
gcloud storage buckets create gs://${TERRAFORM_STATE_BUCKET} \
  --project=${GCP_PROJECT_ID} \
  --location=europe-west1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://${TERRAFORM_STATE_BUCKET} --versioning
```

### **Problème: "Missing GitHub Actions secret"**

**Cause**: `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, ou `GCP_WIF_SERVICE_ACCOUNT` manquant

**Solution**: GitHub > Settings > Secrets and variables > Actions > créer les 3 secrets

### **Problème: "Permission denied" lors du apply**

**Cause**: Service account `terraform-deployer-sa` n'a pas les rôles IAM nécessaires

**Voir**: [docs/infra/iam_roles.md](iam_roles.md)

### **Problème: Error 403 `artifactregistry.repositories.downloadArtifacts` lors de la création du Cloud Run Job**

**Cause**: GCP IAM prend jusqu'à 60 secondes à propager les nouveaux bindings. Terraform créait le Cloud Run Job immédiatement après avoir accordé `roles/artifactregistry.reader`, avant propagation.

**Solution appliquée**: Une ressource `time_sleep` de 60s dans `infra/modules/compute/main.tf` insère un délai entre les IAM members et la création du job. Des `triggers` basés sur les IDs des bindings IAM garantissent que le sleep se relance si les bindings sont modifiés lors d'un apply ultérieur. Aucune action manuelle nécessaire — le prochain apply passera.

---

## 🔟 Résumé rapide

| Composant | Localisation | Contenu |
|-----------|--------------|---------|
| **Secrets CI** | GitHub Secrets | GCP_PROJECT_ID, WIF config |
| **Env vars** | infra-deploy.yml | TF_VAR_*, TF_BACKEND_BUCKET |
| **Code Terraform** | infra/ | variables.tf, main.tf, modules/ |
| **State file** | GCS Bucket | terraform.tfstate (JSON) |
| **Ressources** | GCP | Cloud Run Job (1 mutualisé), BigQuery (datasets + external tables raw), Storage (avec lifecycle Nearline), Scheduler (3 jobs), Secret Manager |
| **Config locale** | .gitignore | terraform.tfvars (ne pas commiter) |

---

**Dernière mise à jour**: Mars 2026  
**Auteur**: Infrastructure team  
**Voir aussi**: [docs/cicd/deployment_orchestration.md](../cicd/deployment_orchestration.md)
