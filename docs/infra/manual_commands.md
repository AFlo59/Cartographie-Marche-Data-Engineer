# Commandes locales — sans Docker

Ce guide couvre l'exécution Terraform avec les outils installés directement sur votre poste.

Pour le setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md)

Pour l'exécution via conteneur : [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md)

> Ce guide sert principalement au **développement local**, à la validation manuelle et au debug.
> Dans le périmètre actuel, le **déploiement principal de l'infrastructure Terraform** doit passer par GitHub Actions après merge sur `main`.

## Quand utiliser ce fichier

Utiliser ce guide si vous avez installé localement :
- `gcloud`,
- `terraform` ou `tofu`,
- et éventuellement Python pour le projet.

Si ce n'est pas le cas, préférez le guide Docker.

Ce guide couvre uniquement l'exécution manuelle de l'infra pendant le développement, pas la release automatique complète du projet.

## Pré-requis

### 1. Se placer à la racine du projet

```powershell
Set-Location "C:\CHEMIN\VERS\Cartographie-Marche-Data-Engineer"
```

Pourquoi : toutes les commandes supposent la racine du repo comme point de départ.

Placeholder utilisé :
- `C:\CHEMIN\VERS\Cartographie-Marche-Data-Engineer` = chemin local réel du repo sur votre poste.

### 2. Vérifier ou créer `.env`

```powershell
Copy-Item .\.env.example .\.env -ErrorAction SilentlyContinue
Get-Content .\.env
```

Pourquoi : vérifier les variables projet, région, comptes de service et image Cloud Run.

### 3. Authentifier `gcloud`

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project cartographie-data-engineer
gcloud auth list
```

Pourquoi : Terraform Google utilisera ADC en local.

## Workflow Terraform local

### 4. Aller dans le dossier infra

```powershell
Set-Location .\infra
```

Pourquoi : les commandes Terraform doivent partir du dossier contenant les fichiers `.tf`.

### 5. Initialiser Terraform

#### Validation locale simple

```powershell
terraform init -backend=false
```

#### Backend GCS réel

Depuis le dossier `infra/`, récupérez le nom du bucket (défini dans le workflow) :

```powershell
# Exemple: datatalent-tfstate-my-gcp-project-id
terraform init -backend-config="bucket=${TERRAFORM_STATE_BUCKET}" -reconfigure
```

Si migration de state depuis local vers GCS:

```powershell
terraform init -backend-config="bucket=${TERRAFORM_STATE_BUCKET}" -migrate-state
```

Où `${TERRAFORM_STATE_BUCKET}` = nom du bucket de state Terraform (ex: `datatalent-tfstate-my-gcp-project-id`)

### 6. Vérifier la configuration

```powershell
terraform fmt -check -recursive
terraform validate
terraform plan
```

Pourquoi : contrôle style, validité et diff avant application.

### 7. Appliquer

```powershell
terraform apply
```

Pourquoi : crée ou met à jour l'infrastructure dans GCP.

### 8. Vérifier les ressources déployées

```powershell
gcloud storage buckets list --project cartographie-data-engineer
bq ls --project_id=cartographie-data-engineer
gcloud run jobs list --region=europe-west1 --project cartographie-data-engineer
gcloud scheduler jobs list --location=europe-west1 --project cartographie-data-engineer
gcloud secrets list --project cartographie-data-engineer
```

Pourquoi : confirme les ressources principales après déploiement.

### 9. Détruire si nécessaire

```powershell
terraform destroy
```

## Dépendances Python du projet

Si vous exécutez aussi les scripts Python localement :

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r ..\requirements.txt
```

Pourquoi : prépare un environnement local pour les scripts d'ingestion.

## Options avancées

### Vous voulez gérer les secrets runtime

Utiliser le guide dédié : [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md)

### Vous préparez la CI GitHub Actions

Utiliser le guide dédié : [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md)

### Vous voulez vérifier les rôles IAM

Utiliser le guide dédié : [docs/infra/iam_roles.md](docs/infra/iam_roles.md)
