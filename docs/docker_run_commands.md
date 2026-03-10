# Commandes Docker — exécution infra

Ce fichier regroupe uniquement les commandes à lancer via Docker pour l'infra (service `infra-iac`).

## 0) Préparer le contexte (obligatoire)

Toutes les commandes ci-dessous doivent être lancées depuis la racine du repo (`Cartographie-Marche-Data-Engineer`).

```bash
cd D:/PROJETS/Cartographie-Marche-Data-Engineer
```

Vérifier que le fichier `.env` existe:

```bash
ls -l .env
```

Si absent:

```bash
cp .env.example .env
```

Vérifier au minimum ces variables dans `.env`:

- `TF_VAR_project_id=cartographie-data-engineer`
- `TF_VAR_region=europe-west1`
- `TF_VAR_location=EU`

## 1) Construire l'image infra

```bash
docker compose build --no-cache infra-iac
```

But: reconstruit l'image avec `terraform`, `tofu` et `gcloud`.

Note architecture: le `Dockerfile` infra est multi-arch (`linux/amd64` et `linux/arm64`) via `TARGETOS`/`TARGETARCH` BuildKit. Aucun `--platform=linux/amd64` n'est requis dans le cas standard.

## 2) Authentification (choisir un seul chemin)

### Option A — Token OAuth (fallback robuste, recommandé si ADC échoue)

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac gcloud auth list
```

Puis lancer Terraform avec token temporaire:

```bash
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform plan'
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform apply'
```

Version explicite avec variable projet (copier-coller):

```bash
docker compose run --rm infra-iac sh -lc 'PROJECT_ID=cartographie-data-engineer; gcloud config set project ${PROJECT_ID}; export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token); terraform init -backend=false; terraform validate; terraform plan'
```

### Option B — ADC (mode standard)

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud auth application-default login
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

But: permet au provider Terraform Google d'utiliser les credentials ADC sans clé JSON (compatible policy entreprise qui interdit la création de clés SA).

Note: le conteneur utilise `GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json`.

Option clé JSON (si autorisée par policy): définir `GOOGLE_APPLICATION_CREDENTIALS=/workspace/secrets/gcp-sa.json` dans `.env` et déposer la clé dans `secrets/gcp-sa.json`.

## 3) Vérifier les outils dans le conteneur

```bash
docker compose run --rm infra-iac terraform version
docker compose run --rm infra-iac gcloud --version
```

But: valider que l'environnement conteneurisé est prêt.

## 4) Valider la configuration Terraform

```bash
docker compose run --rm infra-iac terraform init -backend=false
docker compose run --rm infra-iac terraform validate
docker compose run --rm infra-iac terraform fmt -check -recursive
```

But: vérifier syntaxe/providers/modules avant le déploiement.

Commande unique (init + validate + fmt):

```bash
docker compose run --rm infra-iac sh -lc 'terraform init -backend=false && terraform validate && terraform fmt -check -recursive'
```

## 5) Plan et application (INFRA-01/02/03)

```bash
docker compose run --rm infra-iac terraform plan
docker compose run --rm infra-iac terraform apply
```

But: créer les ressources actuellement implémentées (bucket raw + datasets BigQuery raw/staging/marts).

Si vous utilisez Option A (token OAuth), utilisez ces commandes à la place:

```bash
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform plan'
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform apply -auto-approve'
```

## 6) Vérifications post-déploiement depuis le conteneur

```bash
docker compose run --rm infra-iac gcloud storage buckets list --project cartographie-data-engineer
docker compose run --rm infra-iac bq ls --project_id=cartographie-data-engineer
```

But: confirmer que les ressources existent dans GCP.

## Dépannage rapide

Si `terraform plan` affiche encore une erreur credentials, vérifier que le fichier ADC existe:

```bash
docker compose run --rm infra-iac sh -lc 'ls -l /root/.config/gcloud/application_default_credentials.json'
```

Si absent, relancer:

```bash
docker compose run --rm infra-iac gcloud auth application-default login
```

Si `gcloud` crash encore avec `Scope has changed`, revenir à l'**Option A — Token OAuth** en section 2.

Explication de la commande:

- `gcloud auth print-access-token` génère un token OAuth temporaire.
- `export GOOGLE_OAUTH_ACCESS_TOKEN=...` injecte ce token dans l'environnement du shell du conteneur.
- `terraform plan` / `terraform apply` utilisent ce token via le provider Google.

Important:

- Le token expire rapidement (souvent ~1h).
- Relancer la commande token avant chaque exécution importante (`plan`, puis `apply`).
- Le token n'est pas persisté dans le repo et ne remplace pas une auth service account long terme.

Commande de diagnostic correcte (dans le service `infra-iac`):

```bash
docker compose run --rm infra-iac gcloud info --run-diagnostics
```

## 7) Nettoyage des ressources (si besoin)

Si vous voulez supprimer les ressources créées via Terraform (et seulement celles gérées par le state courant):

```bash
docker compose run --rm infra-iac terraform destroy
```

Si vous utilisez Option A (token OAuth):

```bash
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform destroy -auto-approve'
```
