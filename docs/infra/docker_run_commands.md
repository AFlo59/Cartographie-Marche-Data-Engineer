# Commandes Docker  workflow infra rcurrent

Ce guide couvre uniquement l'excution Terraform via le conteneur `infra-iac`.

Pour le setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)

Pour la vue d'ensemble : [docs/setup_guide.md](../setup_guide.md)

> Ce guide sert principalement au **dveloppement local**,  la validation manuelle et au debug.
> Dans le primtre actuel, le **dploiement principal de l'infrastructure Terraform** doit passer par GitHub Actions aprs merge sur `main`.

## Quand utiliser ce fichier

Utiliser ce guide pour les oprations rcurrentes :
- build de l'image infra,
- authentification locale,
- `init`, `validate`, `plan`, `apply`,
- vrifications aprs dploiement.

Ce guide ne dfinit pas la release fonctionnelle complte du projet : il couvre seulement l'excution manuelle de l'infra pendant le dveloppement.

Les oprations sensibles ou one-shot ont leur guide ddi :
- secrets : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)
- IAM : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- WIF GitHub : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)

## Ordre recommand

### 0. Pr-requis

- Le setup GCP manuel est termin.
- Le fichier `.env` existe.
- Les `TF_VAR_*` ncessaires sont renseigns.

Depuis la racine du repo :

```bash
cd D:/PROJETS/Cartographie-Marche-Data-Engineer
ls -l .env
```

Si `.env` est absent :

```bash
cp .env.example .env
```

Si votre repo n'est pas dans `D:/PROJETS/...`, remplacez le chemin par le chemin local rel du workspace.

### 1. Construire l'image infra

```bash
docker compose build --no-cache infra-iac
```

Pourquoi : reconstruit l'image qui contient `terraform`, `tofu` et `gcloud`.

### 2. Choisir un mode d'authentification local

#### Option A  ADC recommand

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

Pourquoi : c'est le mode standard local quand les cls JSON sont bloques.

#### Option B  OAuth fallback

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac gcloud auth list
```

Puis utiliser le wrapper intgr :

```bash
docker compose run --rm infra-iac terraform-oauth init -reconfigure
docker compose run --rm infra-iac terraform-oauth validate
docker compose run --rm infra-iac terraform-oauth plan
docker compose run --rm infra-iac terraform-oauth apply
```

Pourquoi : `terraform-oauth` rafrachit automatiquement le token OAuth avant chaque commande.

### 3. Initialiser Terraform

#### Backend local temporaire

```bash
docker compose run --rm infra-iac terraform init -backend=false
```

Pourquoi : utile pour valider la config sans toucher au backend GCS.

#### Backend GCS rel

```bash
docker compose run --rm infra-iac terraform init -reconfigure
```

Si vous migrez un state local existant vers GCS :

```bash
docker compose run --rm infra-iac terraform init -migrate-state
```

Pourquoi : initialise le backend rel utilis par les dploiements.

### 4. Vrifier la configuration avant dploiement

```bash
docker compose run --rm infra-iac terraform fmt -check -recursive
docker compose run --rm infra-iac terraform validate
docker compose run --rm infra-iac terraform plan
```

Pourquoi : dtecte les erreurs avant l'application.

### 5. Appliquer l'infrastructure

```bash
docker compose run --rm infra-iac terraform apply
```

Pourquoi : cre ou met  jour les ressources GCP dcrites dans Terraform.

### 6. Vrifier le rsultat ct GCP

```bash
docker compose run --rm infra-iac gcloud storage buckets list --project cartographie-data-engineer
docker compose run --rm infra-iac bq ls --project_id=cartographie-data-engineer
docker compose run --rm infra-iac gcloud run jobs list --region=europe-west1 --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud scheduler jobs list --location=europe-west1 --project cartographie-data-engineer
docker compose run --rm infra-iac gcloud secrets list --project cartographie-data-engineer
```

Pourquoi : confirme bucket, datasets, Cloud Run Job, Scheduler et secrets.

### 7. Dtruire les ressources si ncessaire

```bash
docker compose run --rm infra-iac terraform destroy
```

Pourquoi : supprime les ressources gres par le state courant.

## Commandes utiles par objectif

### Vrifier les versions d'outils du conteneur

```bash
docker compose run --rm infra-iac terraform version
docker compose run --rm infra-iac gcloud --version
```

### Chane rapide `init + validate + fmt`

```bash
docker compose run --rm infra-iac sh -lc 'terraform init -backend=false && terraform validate && terraform fmt -check -recursive'
```

### Plan/apply avec wrapper OAuth

```bash
docker compose run --rm infra-iac terraform-oauth plan
docker compose run --rm infra-iac terraform-oauth apply
```

## Dpannage rapide

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

### Vous devez crer ou peupler les secrets

Ne pas le faire dans ce guide pour viter le doublon.

Guide ddi : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)

### Activer le Cloud Run Job aprs le premier push d'image

Le Cloud Run Job et les Schedulers sont dsactivs par dfaut (`create_compute_job = false`).
GCP choue avec 403 si l'image n'existe pas dans Artifact Registry.

**tape 1**  Builder et pusher l'image d'ingestion :

```bash
# Builder l'image ingestion via docker compose
docker compose build ingestion

# Authentifier Docker sur Artifact Registry
docker compose run --rm infra-iac gcloud auth configure-docker europe-west1-docker.pkg.dev

# Tagger et pousser l'image
docker tag datatalent-ingestion europe-west1-docker.pkg.dev/cartographie-data-engineer/datatalent/ingestion:latest
docker push europe-west1-docker.pkg.dev/cartographie-data-engineer/datatalent/ingestion:latest
```

**tape 2**  Activer le job dans Terraform :

```bash
docker compose run --rm infra-iac terraform apply -var="create_compute_job=true"
```

---

### Activer les External Tables BigQuery aprs la premire ingestion

Les External Tables sont dsactives par dfaut (`create_external_tables = false`).
BigQuery refuse de crer une table avec `autodetect = true` si le bucket est vide.

**tape 1**  Vrifier que des fichiers Parquet existent dans le bucket :

```bash
docker compose run --rm infra-iac gcloud storage ls \
  gs://datatalent-dev-cartographie-data-engineer-raw/raw/sirene/ \
  --project cartographie-data-engineer

docker compose run --rm infra-iac gcloud storage ls \
  gs://datatalent-dev-cartographie-data-engineer-raw/raw/france_travail/ \
  --project cartographie-data-engineer
```

**tape 2**  Dclencher manuellement le Cloud Run Job pour peupler le bucket (recommand) :

```bash
docker compose run --rm infra-iac gcloud run jobs execute datatalent-ingestion-job \
  --region=europe-west1 \
  --project cartographie-data-engineer \
  --update-env-vars INGESTION_SOURCE=france_travail

docker compose run --rm infra-iac gcloud run jobs execute datatalent-ingestion-job \
  --region=europe-west1 \
  --project cartographie-data-engineer \
  --update-env-vars INGESTION_SOURCE=sirene
```

**tape 3**  Une fois les fichiers prsents, appliquer avec les External Tables actives :

```bash
docker compose run --rm infra-iac terraform apply -var="create_external_tables=true"
```

Pour activer en CI : mettre `TF_VAR_create_external_tables: "true"` dans `.github/workflows/infra-deploy.yml`.

Voir le guide complet : [docs/infra/manual_commands.md](../infra/manual_commands.md#activer-les-external-tables-bigquery-aprs-la-premire-ingestion)
