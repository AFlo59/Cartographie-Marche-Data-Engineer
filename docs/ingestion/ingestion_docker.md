# Guide Docker — scripts d'ingestion

Ce document explique comment builder et exécuter les scripts d'ingestion localement via Docker.

Pour l'exécution en production (Cloud Run Job déclenché par Cloud Scheduler), se référer à :
- [docs/cicd/deployment_orchestration.md](../cicd/deployment_orchestration.md)
- [docs/infra/infrastructure_flow.md](../infra/infrastructure_flow.md)

---

## Architecture ingestion

Le module d'ingestion supporte cinq sources de données :

| Source | Script | Fréquence Cloud Scheduler |
| --- | --- | --- |
| `france_travail` | `ingest_france_travail.py` | Hebdomadaire lundi (`0 6 * * 1`) |
| `apec` | `ingest_apec.py` | Hebdomadaire lundi (`0 7 * * 1`) |
| `jooble` | `ingest_jooble.py` | Hebdomadaire lundi (`0 8 * * 1`) |
| `sirene` | `ingest_sirene.py` | Mensuelle (`0 3 1 * *`) |
| `geo` | `ingest_geo.py` | Mensuelle (`0 4 1 * *`) |
| `all` | (enchaîne les 5) | — |

Le point d'entrée est `main.py` qui accepte `--source <source>`.

La variable d'environnement `INGESTION_SOURCE` est utilisée par le Cloud Run Job pour sélectionner la source
(Cloud Scheduler envoie un override d'env var à chaque déclenchement).

---

## Pré-requis

- Docker Desktop / Docker Engine installé
- `.env` renseigné à la racine (copier depuis `.env.example` si absent) :

  ```bash
  cp .env.example .env
  # Renseigner au minimum : GCP_PROJECT_ID, INGESTION_RAW_BUCKET (ou TF_VAR_project_id),
  # FT_CLIENT_ID, FT_CLIENT_SECRET, GOOGLE_APPLICATION_CREDENTIALS
  ```

- Authentification GCP active (ADC recommandé) :

  ```bash
  gcloud auth application-default login
  ```

---

## 1. Builder l'image ingestion

Le build context est `src/ingestion/` (cohérent avec le CI).

```bash
# Depuis la racine du repo
docker compose build ingestion-jobs
```

Ou build direct sans docker-compose :

```bash
docker build -f src/ingestion/Dockerfile -t datatalent-ingestion src/ingestion
```

Pour rebuilder sans cache :

```bash
docker compose build --no-cache ingestion-jobs
```

---

## 2. Exécuter une source spécifique

### Via docker-compose

```bash
# France Travail
docker compose run --rm -e INGESTION_SOURCE=france_travail ingestion-jobs

# APEC
docker compose run --rm -e INGESTION_SOURCE=apec ingestion-jobs

# Jooble
docker compose run --rm -e INGESTION_SOURCE=jooble ingestion-jobs

# Sirène
docker compose run --rm -e INGESTION_SOURCE=sirene ingestion-jobs

# API Géo
docker compose run --rm -e INGESTION_SOURCE=geo ingestion-jobs

# Toutes les sources (enchaîne les 5)
docker compose run --rm -e INGESTION_SOURCE=all ingestion-jobs
```

### Via docker run direct

```bash
docker run --rm \
  --env-file .env \
  -e INGESTION_SOURCE=france_travail \
  -v "${HOME}/.config/gcloud:/root/.config/gcloud:ro" \
  datatalent-ingestion
```

Remplacer `INGESTION_SOURCE=france_travail` par `sirene`, `geo` ou `all` selon la source.

---

## 3. Passer la source via l'argument CLI

Le `main.py` accepte aussi `--source` directement, ce qui permet de surcharger la variable d'environnement :

```bash
docker compose run --rm ingestion-jobs python main.py --source france_travail
docker compose run --rm ingestion-jobs python main.py --source apec
docker compose run --rm ingestion-jobs python main.py --source jooble
docker compose run --rm ingestion-jobs python main.py --source sirene
docker compose run --rm ingestion-jobs python main.py --source geo
docker compose run --rm ingestion-jobs python main.py --source all
```

---

## 4. Variables d'environnement requises au runtime

Ces variables sont lues par les scripts depuis l'environnement (`.env` ou env CI/Cloud Run) :

| Variable | Obligatoire | Description |
| --- | --- | --- |
| `GCP_PROJECT_ID` | ✅ | Projet GCP cible |
| `INGESTION_RAW_BUCKET` | ✅ | Bucket GCS de destination (format : `datatalent-<env>-<project_id>-raw`) |
| `INGESTION_SOURCE` | ✅ (ou `--source`) | Source à ingérer : `france_travail`, `apec`, `jooble`, `sirene`, `geo`, `all` |
| `GOOGLE_APPLICATION_CREDENTIALS` | ✅ | Chemin vers ADC ou clé JSON SA |
| `FT_CLIENT_ID` | ✅ (france_travail) | Client ID OAuth France Travail |
| `FT_CLIENT_SECRET` | ✅ (france_travail) | Client Secret OAuth France Travail |
| `JOOBLE_API_KEY` | ✅ (jooble) | Clé API Jooble |
| `INGESTION_FRANCE_TRAVAIL_PREFIX` | optionnel | Préfixe GCS (défaut : `raw/france_travail/`) |
| `INGESTION_APEC_PREFIX` | optionnel | Préfixe GCS (défaut : `raw/apec/`) |
| `INGESTION_JOOBLE_PREFIX` | optionnel | Préfixe GCS (défaut : `raw/jooble/`) |
| `INGESTION_SIRENE_PREFIX` | optionnel | Préfixe GCS (défaut : `raw/sirene/`) |
| `INGESTION_GEO_PREFIX` | optionnel | Préfixe GCS (défaut : `raw/geo/`) |

En production (Cloud Run Job), `FT_CLIENT_ID`, `FT_CLIENT_SECRET` et `JOOBLE_API_KEY` sont lus depuis Secret Manager.
En local, ils peuvent être définis directement dans `.env`.

---

## 5. Vérifier les fichiers uploadés dans GCS

Après une exécution, vérifier que les fichiers Parquet ont été créés :

```bash
# Charger les variables depuis .env
source .env  # (Linux/Mac) — ou définir manuellement sous Windows

# Vérifier les fichiers dans GCS
gcloud storage ls gs://${INGESTION_RAW_BUCKET}/raw/france_travail/ --project=${GCP_PROJECT_ID}
gcloud storage ls gs://${INGESTION_RAW_BUCKET}/raw/sirene/ --project=${GCP_PROJECT_ID}
gcloud storage ls gs://${INGESTION_RAW_BUCKET}/raw/geo/ --project=${GCP_PROJECT_ID}
```

---

## 6. Builder et pousser l'image vers Artifact Registry (manuel)

En CI, le push est géré automatiquement par le job `push-images` de `infra-deploy.yml` après un merge sur `main`.

Pour un push manuel (test ou urgence) :

```bash
# Variables à adapter depuis .env
AR_REGION="${GCP_REGION:-us-central1}"
AR_REPO="datatalent"
GCP_PROJECT_ID="${GCP_PROJECT_ID}"

INGESTION_IMAGE="${AR_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO}/ingestion:latest"

# Authentifier Docker vers Artifact Registry
gcloud auth configure-docker ${AR_REGION}-docker.pkg.dev

# Builder et pousser
docker build -f src/ingestion/Dockerfile -t ${INGESTION_IMAGE} src/ingestion
docker push ${INGESTION_IMAGE}

# Vérifier
gcloud artifacts docker images list ${AR_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO} \
  --project=${GCP_PROJECT_ID}
```

---

## 7. Dépannage

### Erreur d'authentification GCP

```bash
# Vérifier que ADC est configuré
gcloud auth application-default print-access-token

# Si absent, se connecter
gcloud auth application-default login
```

### Erreur de connexion au bucket GCS

Vérifier que `INGESTION_RAW_BUCKET` est renseigné dans `.env` et que `ingestion-sa` a `roles/storage.objectAdmin` sur le bucket.

### La variable INGESTION_SOURCE n'est pas reconnue

Vérifier que la valeur est bien parmi : `france_travail`, `apec`, `jooble`, `sirene`, `geo`, `all` (case-insensitive).

### Accès refusé aux secrets Secret Manager

En local, utiliser les variables directement dans `.env` (`FT_CLIENT_ID`, `FT_CLIENT_SECRET`).
Le Secret Manager est utilisé uniquement dans le contexte Cloud Run Job.

---

## Référence croisée

- IAM ingestion-sa : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- Setup Secret Manager : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)
- CI/CD images : [docs/infra/infrastructure_flow.md](../infra/infrastructure_flow.md)
- Déclencher le Cloud Run Job manuellement : [docs/infra/manual_commands.md](../infra/manual_commands.md)
