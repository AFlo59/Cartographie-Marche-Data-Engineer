# Commandes Docker — exécution infra

Ce fichier regroupe uniquement les commandes à lancer via Docker pour l'infra (service `infra-iac`).

## 1) Construire l'image infra

```bash
docker compose build --no-cache infra-iac
```

But: reconstruit l'image avec `terraform`, `tofu` et `gcloud`.

## 2) Authentifier gcloud dans le conteneur

```bash
docker compose run --rm infra-iac gcloud auth login
docker compose run --rm infra-iac gcloud auth application-default login --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/userinfo.email
docker compose run --rm infra-iac gcloud config set project cartographie-data-engineer
```

But: permet au provider Terraform Google d'utiliser les credentials ADC sans clé JSON (compatible policy entreprise qui interdit la création de clés SA).

Note: le conteneur utilise `GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json`.

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

## 5) Plan et application (INFRA-01/02/03)

```bash
docker compose run --rm infra-iac terraform plan
docker compose run --rm infra-iac terraform apply
```

But: créer les ressources actuellement implémentées (bucket raw + datasets BigQuery raw/staging/marts).

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
docker compose run --rm infra-iac gcloud auth application-default login --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/userinfo.email,openid
```

Si `gcloud` crash avec `Scope has changed`, utiliser le fallback sans ADC:

```bash
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform plan'
docker compose run --rm infra-iac sh -lc 'export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) && terraform apply'
```

Ce fallback utilise le token utilisateur actif de `gcloud auth login` et contourne le bug `application-default login`.

Explication de la commande:

- `gcloud auth print-access-token` génère un token OAuth temporaire.
- `export GOOGLE_OAUTH_ACCESS_TOKEN=...` injecte ce token dans l'environnement du shell du conteneur.
- `terraform plan` / `terraform apply` utilisent ce token via le provider Google.

Important:

- Le token expire rapidement (souvent ~1h).
- Relancer la même commande `sh -lc 'export ... && terraform ...'` pour chaque exécution importante (`plan`, puis `apply`).
- Le token n'est pas persisté dans le repo et ne remplace pas une auth service account long terme.

Commande de diagnostic correcte (dans le service `infra-iac`):

```bash
docker compose run --rm infra-iac gcloud info --run-diagnostics
```
