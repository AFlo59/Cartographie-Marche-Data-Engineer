# Setup GCP manuel  tapes one-shot

Ce guide couvre uniquement les oprations manuelles  excuter une seule fois dans GCP Cloud Shell avant de lancer Terraform.

Primtre actuel : prparation du socle ncessaire aux tickets INFRA-02  INFRA-06, plus la base d'authentification pour INFRA-09 ct dploiement infra.

Pour les excutions rcurrentes :
- Docker : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- Installation locale : [docs/infra/manual_commands.md](../infra/manual_commands.md)

Pour la vue d'ensemble : [docs/setup_guide.md](../setup_guide.md)

## Quand utiliser ce fichier

Utiliser ce guide pour :
- prparer le projet GCP,
- activer les APIs ncessaires,
- crer les service accounts,
- donner les droits au compte de dploiement,
- vrifier que le socle GCP est prt.

## Ordre des tapes

### 1. Slectionner le projet

```bash
gcloud config set project cartographie-data-engineer
```

Pourquoi : fixe le projet actif pour toutes les commandes suivantes.

### 2. Vrifier le contexte projet

```bash
gcloud projects describe cartographie-data-engineer --format="value(projectId,projectNumber,parent.type,parent.id)"
```

Pourquoi : confirme le projet, le project number et le parent org/folder.

### 3. Vrifier les tags d'organisation si ncessaire

Cette tape est optionnelle et dpend des policies de votre organisation.

```bash
gcloud resource-manager tags bindings list --parent=//cloudresourcemanager.googleapis.com/projects/cartographie-data-engineer
```

Pourquoi : certaines organisations exigent un tag `environment` avant d'autoriser certains usages.

Si vous devez crer ou binder le tag, utiliser la section dtaille plus bas dans ce mme fichier.

### 4. Activer les APIs ncessaires

```bash
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project cartographie-data-engineer
```

Pourquoi : prpare les services requis par l'infra actuelle et la CI WIF.

### 5. Crer les service accounts

```bash
gcloud iam service-accounts create ingestion-sa --display-name="Ingestion SA"
gcloud iam service-accounts create dbt-sa --display-name="DBT SA"
gcloud iam service-accounts create dashboard-sa --display-name="Dashboard SA"
gcloud iam service-accounts create scheduler-sa --display-name="Scheduler SA"
gcloud iam service-accounts create terraform-deployer-sa --display-name="Terraform Deployer SA"
```

Pourquoi : chaque usage a son identit ddie. `scheduler-sa` reste optionnel mais recommand pour isoler les responsabilits.

### 6. Rcuprer les emails  reporter dans `.env`

```bash
gcloud iam service-accounts list --format="table(email,displayName)"
```

Pourquoi : ces emails alimentent `TF_VAR_ingestion_service_account_email`, `TF_VAR_dbt_service_account_email`, `TF_VAR_dashboard_service_account_email` et ventuellement `TF_VAR_scheduler_service_account_email`.

### 7. Donner les rles au compte de dploiement Terraform

```bash
TF_SA="terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com"
PROJECT="cartographie-data-engineer"
INGESTION_SA="ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com"

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

gcloud iam service-accounts add-iam-policy-binding ${INGESTION_SA} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=${PROJECT}
```

Pourquoi : ce compte est utilis par Terraform en local et en CI pour crer et mettre  jour les ressources du primtre infra actuel.

La matrice complte des rles est documente dans [docs/infra/iam_roles.md](../infra/iam_roles.md).

### 8. Vrifier que le projet est prt

```bash
gcloud services list --enabled --project cartographie-data-engineer \
  --filter="name:(storage.googleapis.com OR bigquery.googleapis.com OR run.googleapis.com OR cloudscheduler.googleapis.com OR secretmanager.googleapis.com)"

gcloud projects get-iam-policy cartographie-data-engineer \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:terraform-deployer-sa@cartographie-data-engineer.iam.gserviceaccount.com" \
  --format="table(bindings.role)"

gcloud iam service-accounts get-iam-policy ingestion-sa@cartographie-data-engineer.iam.gserviceaccount.com \
  --project=cartographie-data-engineer
```

Pourquoi : confirme les APIs actives, les rles projet du deployer et le binding `iam.serviceAccountUser`.

### 9. tape suivante

Une fois ce socle prt :
- excuter Terraform via [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md),
- ou via [docs/infra/manual_commands.md](../infra/manual_commands.md),
- puis charger les valeurs relles des secrets via [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md).

## Option avance  tags d'organisation

Placeholders utiliss dans cette section :

- `ORG_ID` = identifiant numrique de l'organisation GCP parente.
- `TAG_KEY_ID` = identifiant numrique de la cl de tag GCP.
- `TAG_VALUE_ID` = identifiant numrique de la valeur de tag  binder au projet.
- `YOUR_EMAIL` = adresse email de l'utilisateur  autoriser temporairement pour manipuler les tags.

### Vrifier les tags disponibles

```bash
gcloud projects describe cartographie-data-engineer --format="value(parent.id)"
gcloud resource-manager tags keys list --parent=organizations/ORG_ID --format="table(name,shortName)"
gcloud resource-manager tags values list --parent=tagKeys/TAG_KEY_ID --format="table(name,shortName)"
```

### Binder une valeur de tag existante

```bash
gcloud resource-manager tags bindings create \
  --parent=//cloudresourcemanager.googleapis.com/projects/cartographie-data-engineer \
  --tag-value=tagValues/TAG_VALUE_ID
```

### Crer la cl `environment` si vous tes admin org

```bash
gcloud resource-manager tags keys create environment \
  --parent=organizations/ORG_ID \
  --description="Environment tag for projects"

gcloud resource-manager tags values create Development --parent=tagKeys/TAG_KEY_ID
gcloud resource-manager tags values create Test --parent=tagKeys/TAG_KEY_ID
gcloud resource-manager tags values create Staging --parent=tagKeys/TAG_KEY_ID
gcloud resource-manager tags values create Production --parent=tagKeys/TAG_KEY_ID
```

### Dpannage `PERMISSION_DENIED` sur les tags

```bash
gcloud projects add-iam-policy-binding cartographie-data-engineer \
  --member="user:YOUR_EMAIL" \
  --role="roles/resourcemanager.tagUser"

gcloud resource-manager tags values add-iam-policy-binding tagValues/TAG_VALUE_ID \
  --member="user:YOUR_EMAIL" \
  --role="roles/resourcemanager.tagUser"
```

Pourquoi : il faut souvent `roles/resourcemanager.tagUser`  la fois sur le projet et sur la valeur de tag.

## Option avance  authentification CI GitHub

Ne pas dtailler WIF ici pour viter le doublon.

Guide ddi : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)
