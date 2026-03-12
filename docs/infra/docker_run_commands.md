# Commandes Docker — workflow infra récurrent

Ce guide couvre uniquement l'exécution Terraform via le conteneur `infra-iac`.

Pour le setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md)

Pour la vue d'ensemble : [docs/setup_guide.md](docs/setup_guide.md)

> Ce guide sert principalement au **développement local**, à la validation manuelle et au debug.
> Dans le périmètre actuel, le **déploiement principal de l'infrastructure Terraform** doit passer par GitHub Actions après merge sur `main`.

## Quand utiliser ce fichier

Utiliser ce guide pour les opérations récurrentes :
- build de l'image infra,
- authentification locale,
- `init`, `validate`, `plan`, `apply`,
- vérifications après déploiement.

Ce guide ne définit pas la release fonctionnelle complète du projet : il couvre seulement l'exécution manuelle de l'infra pendant le développement.

Les opérations sensibles ou one-shot ont leur guide dédié :
- secrets : [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md)
- IAM : [docs/infra/iam_roles.md](docs/infra/iam_roles.md)
- WIF GitHub : [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md)

## Ordre recommandé

### 0. Pré-requis

- Le setup GCP manuel est terminé.
- Le fichier `.env` existe.
- Les `TF_VAR_*` nécessaires sont renseignés.

Depuis la racine du repo :

```bash
cd D:/PROJETS/Cartographie-Marche-Data-Engineer
ls -l .env
```

Si `.env` est absent :

```bash
cp .env.example .env
```

Si votre repo n'est pas dans `D:/PROJETS/...`, remplacez le chemin par le chemin local réel du workspace.

### 1. Construire l'image infra

```bash
docker compose build --no-cache infra-iac
```

Pourquoi : reconstruit l'image qui contient `terraform`, `tofu` et `gcloud`.

### 2. Choisir un mode d'authentification local

#### Option A — ADC recommandé

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

Pourquoi : c'est le mode standard local quand les clés JSON sont bloquées.

#### Option B — OAuth fallback

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac gcloud auth list
```

Puis utiliser le wrapper intégré :

```bash
docker compose run --rm infra-iac terraform-oauth init -reconfigure
docker compose run --rm infra-iac terraform-oauth validate
docker compose run --rm infra-iac terraform-oauth plan
docker compose run --rm infra-iac terraform-oauth apply
```

Pourquoi : `terraform-oauth` rafraîchit automatiquement le token OAuth avant chaque commande.

### 3. Initialiser Terraform

#### Backend local temporaire

```bash
docker compose run --rm infra-iac terraform init -backend=false
```

Pourquoi : utile pour valider la config sans toucher au backend GCS.

#### Backend GCS réel

```bash
docker compose run --rm infra-iac terraform init -reconfigure
```

Si vous migrez un state local existant vers GCS :

```bash
docker compose run --rm infra-iac terraform init -migrate-state
```

Pourquoi : initialise le backend réel utilisé par les déploiements.

### 4. Vérifier la configuration avant déploiement

```bash
docker compose run --rm infra-iac terraform fmt -check -recursive
docker compose run --rm infra-iac terraform validate
docker compose run --rm infra-iac terraform plan
```

Pourquoi : détecte les erreurs avant l'application.

### 5. Appliquer l'infrastructure

```bash
docker compose run --rm infra-iac terraform apply
```

Pourquoi : crée ou met à jour les ressources GCP décrites dans Terraform.

### 6. Vérifier le résultat côté GCP

```bash
docker compose run --rm infra-iac gcloud storage buckets list --project cartographie-data-engineer
docker compose run --rm infra-iac bq ls --project_id=cartographie-data-engineer
docker compose run --rm infra-iac gcloud run jobs list --region=europe-west1 --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud scheduler jobs list --location=europe-west1 --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets list --project cartographie-data-engineer
```

Pourquoi : confirme bucket, datasets, Cloud Run Job, Scheduler et secrets.

### 7. Détruire les ressources si nécessaire

```bash
docker compose run --rm infra-iac terraform destroy
```

Pourquoi : supprime les ressources gérées par le state courant.

## Commandes utiles par objectif

### Vérifier les versions d'outils du conteneur

```bash
docker compose run --rm infra-iac terraform version
docker compose run --rm infra-iac gcloud --version
```

### Chaîne rapide `init + validate + fmt`

```bash
docker compose run --rm infra-iac sh -lc 'terraform init -backend=false && terraform validate && terraform fmt -check -recursive'
```

### Plan/apply avec wrapper OAuth

```bash
docker compose run --rm infra-iac terraform-oauth plan
docker compose run --rm infra-iac terraform-oauth apply
```

## Dépannage rapide

### Le fichier ADC n'existe pas

```bash
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

### Erreur de credentials persistante

Basculez temporairement sur l'option OAuth :

```bash
docker compose run --rm infra-iac terraform-oauth plan
```

### Vous devez créer ou peupler les secrets

Ne pas le faire dans ce guide pour éviter le doublon.

Guide dédié : [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md)
