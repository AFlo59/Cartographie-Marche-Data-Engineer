# Setup GCP manuel — étapes one-shot

Ce guide couvre uniquement les opérations manuelles à exécuter une seule fois dans GCP Cloud Shell avant de lancer Terraform.

Périmètre actuel : préparation du socle nécessaire aux tickets INFRA-02 à INFRA-06, plus la base d'authentification pour INFRA-09 côté déploiement infra.

Pour les exécutions récurrentes :

- Docker : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- Installation locale : [docs/infra/manual_commands.md](../infra/manual_commands.md)

Pour la vue d'ensemble : [docs/setup_guide.md](../setup_guide.md)

---

## Variables de configuration

Définir ces variables **une seule fois** au début de votre session Cloud Shell. Toutes les commandes de ce guide les utilisent — il suffit de changer les valeurs ici pour adapter le guide à un autre projet.

```bash
# ═══════════════════════════════════════════════════════════════
# Variables — adapter à votre projet avant d'exécuter ce guide
# ═══════════════════════════════════════════════════════════════
PROJECT_ID="votre-projet-gcp"              # ← ID de votre projet GCP
REGION="europe-west1"                       # ← région GCP (Cloud Run, Scheduler, AR)

# Comptes de service (construits automatiquement à partir de PROJECT_ID)
TF_SA="terraform-deployer-sa@${PROJECT_ID}.iam.gserviceaccount.com"
INGESTION_SA="ingestion-sa@${PROJECT_ID}.iam.gserviceaccount.com"
DBT_SA="dbt-sa@${PROJECT_ID}.iam.gserviceaccount.com"
DASHBOARD_SA="dashboard-sa@${PROJECT_ID}.iam.gserviceaccount.com"
SCHEDULER_SA="${INGESTION_SA}"              # ← scheduler utilise ingestion-sa par défaut
```

Toutes les commandes du guide utilisent ces variables — il suffit de les définir une fois en début de session.

---

## Quand utiliser ce fichier

Utiliser ce guide pour :

- préparer le projet GCP,
- activer les APIs nécessaires,
- créer les comptes de service,
- donner les droits au compte de déploiement,
- vérifier que le socle GCP est prêt.

---

## Ordre des étapes

### 1. Sélectionner le projet

```bash
gcloud config set project ${PROJECT_ID}
```

Pourquoi : fixe le projet actif pour toutes les commandes suivantes.

### 2. Vérifier le contexte projet

```bash
gcloud projects describe ${PROJECT_ID} \
  --format="value(projectId,projectNumber,parent.type,parent.id)"
```

Pourquoi : confirme le projet, le project number et le parent org/folder.

### 3. Vérifier les tags d'organisation si nécessaire

Cette étape est optionnelle et dépend des policies de votre organisation.

```bash
gcloud resource-manager tags bindings list \
  --parent=//cloudresourcemanager.googleapis.com/projects/${PROJECT_ID}
```

Pourquoi : certaines organisations exigent un tag `environment` avant d'autoriser certains usages.

Si vous devez créer ou binder le tag, utiliser la section optionnelle en bas de ce guide.

### 4. Activer les APIs nécessaires

```bash
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project ${PROJECT_ID}
```

Pourquoi : prépare les services requis par l'infra actuelle et la CI WIF.

### 5. Créer les comptes de service

```bash
gcloud iam service-accounts create ingestion-sa \
  --display-name="Ingestion SA" \
  --project=${PROJECT_ID}

gcloud iam service-accounts create dbt-sa \
  --display-name="DBT SA" \
  --project=${PROJECT_ID}

gcloud iam service-accounts create dashboard-sa \
  --display-name="Dashboard SA" \
  --project=${PROJECT_ID}

gcloud iam service-accounts create scheduler-sa \
  --display-name="Scheduler SA" \
  --project=${PROJECT_ID}

gcloud iam service-accounts create terraform-deployer-sa \
  --display-name="Terraform Deployer SA" \
  --project=${PROJECT_ID}
```

Pourquoi : chaque usage a son identité dédiée. `scheduler-sa` reste optionnel mais recommandé pour isoler les responsabilités.

### 6. Vérifier les emails créés

```bash
gcloud iam service-accounts list \
  --format="table(email,displayName)" \
  --project=${PROJECT_ID}
```

Pourquoi : ces emails alimentent `TF_VAR_ingestion_service_account_email`, `TF_VAR_dbt_service_account_email`, etc.

Les emails sont construits automatiquement par les variables définies en début de guide :

- `${INGESTION_SA}` → `ingestion-sa@${PROJECT_ID}.iam.gserviceaccount.com`
- `${DBT_SA}` → `dbt-sa@${PROJECT_ID}.iam.gserviceaccount.com`
- `${DASHBOARD_SA}` → `dashboard-sa@${PROJECT_ID}.iam.gserviceaccount.com`
- `${TF_SA}` → `terraform-deployer-sa@${PROJECT_ID}.iam.gserviceaccount.com`

### 7. Donner les rôles au compte de déploiement Terraform

```bash
# Ressources infra de base
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/bigquery.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/artifactregistry.admin"

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

Pourquoi : ce compte est utilisé par Terraform en local et en CI pour créer et mettre à jour les ressources du périmètre infra actuel.

La matrice complète des rôles est documentée dans [docs/infra/iam_roles.md](../infra/iam_roles.md).

### 8. Vérifier que le projet est prêt

```bash
# APIs actives
gcloud services list --enabled --project ${PROJECT_ID} \
  --filter="name:(storage.googleapis.com OR bigquery.googleapis.com OR run.googleapis.com OR cloudscheduler.googleapis.com OR secretmanager.googleapis.com)"

# Rôles du deployer SA
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${TF_SA}" \
  --format="table(bindings.role)"

# Binding iam.serviceAccountUser sur ingestion-sa
gcloud iam service-accounts get-iam-policy ${INGESTION_SA} \
  --project=${PROJECT_ID}
```

Pourquoi : confirme les APIs actives, les rôles projet du deployer et le binding `iam.serviceAccountUser`.

### 9. Étape suivante

Une fois ce socle prêt :

- exécuter Terraform via [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md),
- ou via [docs/infra/manual_commands.md](../infra/manual_commands.md),
- puis charger les valeurs réelles des secrets via [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md).

---

## Option avancée — tags d'organisation

Placeholders utilisés dans cette section :

- `ORG_ID` = identifiant numérique de l'organisation GCP parente.
- `TAG_KEY_ID` = identifiant numérique de la clé de tag GCP.
- `TAG_VALUE_ID` = identifiant numérique de la valeur de tag à binder au projet.
- `YOUR_EMAIL` = adresse email de l'utilisateur à autoriser temporairement pour manipuler les tags.

### Vérifier les tags disponibles

```bash
gcloud projects describe ${PROJECT_ID} --format="value(parent.id)"
gcloud resource-manager tags keys list --parent=organizations/ORG_ID --format="table(name,shortName)"
gcloud resource-manager tags values list --parent=tagKeys/TAG_KEY_ID --format="table(name,shortName)"
```

### Binder une valeur de tag existante

```bash
gcloud resource-manager tags bindings create \
  --parent=//cloudresourcemanager.googleapis.com/projects/${PROJECT_ID} \
  --tag-value=tagValues/TAG_VALUE_ID
```

### Créer la clé `environment` si vous êtes admin org

```bash
gcloud resource-manager tags keys create environment \
  --parent=organizations/ORG_ID \
  --description="Environment tag for projects"

gcloud resource-manager tags values create Development --parent=tagKeys/TAG_KEY_ID
gcloud resource-manager tags values create Test --parent=tagKeys/TAG_KEY_ID
gcloud resource-manager tags values create Staging --parent=tagKeys/TAG_KEY_ID
gcloud resource-manager tags values create Production --parent=tagKeys/TAG_KEY_ID
```

### Dépannage `PERMISSION_DENIED` sur les tags

```bash
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="user:YOUR_EMAIL" \
  --role="roles/resourcemanager.tagUser"

gcloud resource-manager tags values add-iam-policy-binding tagValues/TAG_VALUE_ID \
  --member="user:YOUR_EMAIL" \
  --role="roles/resourcemanager.tagUser"
```

Pourquoi : il faut souvent `roles/resourcemanager.tagUser` à la fois sur le projet et sur la valeur de tag.

---

## Option avancée — authentification CI GitHub

Ne pas détailler WIF ici pour éviter le doublon.

Guide dédié : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)
