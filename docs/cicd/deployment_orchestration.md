# Orchestration du projet — vue d'ensemble

Ce document décrit l'enchaînement global des composants du projet sans répéter les guides d'exécution détaillés.

## Flux cible

1. Le socle GCP est préparé manuellement.
2. Terraform déploie l'infrastructure.
3. Les secrets runtime sont versionnés dans Secret Manager.
4. Cloud Scheduler déclenche le Cloud Run Job d'ingestion.
5. Les données brutes arrivent dans **GCS (bucket raw)**. BigQuery y accède via des **External Tables** (pas de copie ni de stockage BQ facturé pour la couche raw).
6. dbt transforme les données via les External Tables → `staging` (views) → `intermediate` (tables incremental) → `marts` (tables dims/faits + views).
7. La restitution est **externe au projet** : le Looker Studio d'un collègue consomme `marts` en lecture seule (aucun outil BI provisionné ici).

## Décision d'architecture ingestion (recommandée)

### Choix retenu

- **Un seul Cloud Run Job** d'ingestion (`datatalent-ingestion-job`),
- **2 jobs Cloud Scheduler d'ingestion** regroupés par fréquence : `weekly`
  (france_travail + apec + jooble) et `monthly` (sirene + geo) — soit **3 jobs
  Cloud Scheduler au total** avec le job `dbt`,
- chaque scheduler envoie un override de variable d'environnement `INGESTION_SOURCE`
  (`weekly` / `monthly`), dispatché vers les sources individuelles par `main.py`.

Ce choix est le plus optimisé actuellement pour votre projet (coût + simplicité opérationnelle).

### Pourquoi c'est le plus efficace aujourd'hui

- une seule image Docker à builder/pusher,
- un seul job Cloud Run à maintenir,
- moins de surface IAM/Terraform,
- coût d'exploitation global souvent plus faible (fréquence faible: hebdo + mensuel).

### Est-ce qu'on "overwrite" les données d'ingestion ?

Recommandation:

- **ne pas écraser le même objet** à chaque run,
- écrire par **source + période d'exécution** (ex: `raw/<source>/YYYY/MM/` ou `raw/<source>/run_date=YYYY-MM-DD/`),
- garder un pointeur "latest" si besoin (facultatif), mais conserver l'historique brut.

Avec cette stratégie, un seul job reste propre et traçable sans collision entre sources.

### Quand passer à plusieurs Cloud Run Jobs distincts

Basculer vers des jobs séparés uniquement si :

- CPU/RAM/timeout très différents par source,
- cadence très différente (ex: une source quotidienne lourde),
- besoin d'isolation forte des incidents/SLA.

Sinon, garder **1 job paramétré** (actuel) est la meilleure option.

## Note coût (ordre de grandeur)

- À faible volumétrie, la différence de coût pur entre 1 job paramétré et 3 jobs séparés est généralement faible.
- Le vrai gain vient surtout de :
	- limiter CPU/RAM au strict besoin,
	- réduire la durée d'exécution,
	- éviter les re-téléchargements complets inutiles,
	- gérer l'incrémental quand l'API le permet.

### Optimisations coût appliquées

| Levier | Économie estimée | Implémenté |
| --- | --- | --- |
| 1 Cloud Run Job mutualisé (vs 3 séparés) | ~60% Artifact Registry + ops | ✅ |
| BigQuery External Tables pour raw (Sirene 10M+ lignes) | ~2-5€/mois stockage BQ | ✅ |
| Purge GCS par source à 30/31 j (1 mois de rétention) | ~40% stockage raw | ✅ |
| Workload Identity Federation (vs clés JSON) | 0 rotation + 0 coût | ✅ |
| Looker Studio (vs Metabase Cloud Run) | ~10-20€/mois | ✅ (recommandé DASH-01) |
| `require_partition_filter: true` sur les tables Sirene dbt | Évite scans > 1To accidentels | ✅ (backlog DBT-07) |

> Transition NEARLINE désactivée (`bucket_nearline_age_days = null`) : la facturation
> minimale NEARLINE de 30 j entrerait en conflit avec la purge par source à 30/31 j.

**Cible** : < 5€/mois hors free tier GCP (1 To/mois queries BQ, 5 Go storage BQ, 3 Scheduler jobs, 2M Cloud Run invocations).

## Pipeline CI/CD — workflow `infra-deploy.yml` (push main)

Le workflow unique `infra-deploy.yml` orchestre tout sur push `main` en 4 jobs :

| Job | Rôle | Déclencheur |
| --- | --- | --- |
| `ingestion-verify` | Build Dockerfile ingestion (vérification validité) | Toujours |
| `dbt-verify` | Build image dbt + `dbt parse` + `dbt compile` | Toujours |
| `push-images` | Build + push `ingestion:latest` et `dbt:latest` vers AR | needs: [ingestion-verify, dbt-verify], merge `main` seulement |
| `terraform` | `terraform plan` sur PR, puis `terraform import` + `terraform apply` après merge sur `main` | needs: [ingestion-verify, dbt-verify, push-images] |

Sur **PR** vers `develop` ou `main` : seuls `ingestion-verify` + `dbt-verify` + `terraform plan` s'exécutent.

Sur **merge vers `main`** : `push-images` (l'image doit exister dans AR avant la création du Cloud Run Job), puis `terraform import` + `terraform apply`.

Workflows séparés `dbt-ci.yml` / `ingestion-ci.yml` et `python-lint.yml` : déclenchés uniquement sur PR et limités à la vérification locale.

Le push Artifact Registry ne doit être fait que par `push-images` dans `infra-deploy.yml`, sinon un second push du même `${GITHUB_SHA::8}` retague la nouvelle image et laisse la précédente sans tag.

## Périmètre actuel documenté

La documentation opérationnelle couvre :

- provisioning Terraform des ressources GCP,
- IAM nécessaire au fonctionnement des modules infra,
- chargement des secrets runtime,
- release infra + images Docker via GitHub Actions (`infra-deploy.yml`).

Les étapes dbt run/test et dashboard sont rappelées ici pour la vision cible, mais ne sont pas encore intégrées dans le pipeline CI (INFRA-09 partiel).

## Guides à suivre selon l'étape

- setup initial : [docs/setup_guide.md](../setup_guide.md)
- préparation GCP : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- exécution Terraform via Docker : [docs/infra/docker_run_commands.md](../infra/docker_run_commands.md)
- exécution Terraform locale : [docs/infra/manual_commands.md](../infra/manual_commands.md)
- secrets runtime : [docs/platform/secret_manager_setup.md](../platform/secret_manager_setup.md)
- CI GitHub ↔ GCP (WIF + IAM SA) : [docs/cicd/github_wif_setup.md](../cicd/github_wif_setup.md)
- matrice IAM complète : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- statut tickets INFRA : [docs/infra/infra_epic4_status.md](../infra/infra_epic4_status.md)

## État actuel synthétique

**Créé par Terraform (activé par défaut) :**
- Bucket raw GCS avec purge lifecycle par source (30/31 j) — NEARLINE désactivé
- Datasets BigQuery `raw`, `staging`, `intermediate`, `marts`
- IAM complet : tous les SA (ingestion, dbt, dashboard, CI) — y compris IAM Artifact Registry préparés en avance
- Secret Manager (4 secrets) + bindings `secretAccessor` pour `ingestion-sa`
- Artifact Registry repo `datatalent` (images ingestion + dbt)
- Pipeline CI : verify ingestion + verify dbt → push images → terraform apply (sur merge main)

**Activé en CI (`infra-deploy.yml`), désactivé par défaut en local :**
- `create_compute_job = true` (CI) : Cloud Run Job ingestion + 3 Schedulers — activer en local après premier push image réussi
- `create_dbt_job = true` (CI) : Cloud Run Job dbt — activer en local après premier push image dbt réussi
- `create_external_tables = true` (CI) : 8 External Tables `raw.*` (france_travail, apec, jooble, sirene ×2, geo ×3) — activer après la première ingestion (BQ autodetect requiert des fichiers Parquet)

**Opt-in (désactivé tant que non configuré) :**
- `create_monitoring` : alert policies Cloud Run Job + canaux email — fournir `alert_emails`
- `billing_export_dataset_id` : binding IAM dbt-sa `dataViewer` sur l'export billing → marts de coûts. Le dataset `billing_export` est **créé manuellement dans GCP** (hors Terraform/CI) ; Terraform ne gère que le binding

**Conteneurs Docker disponibles :** `infra-iac` (Terraform), `ingestion` (Python), `dbt` (dbt-bigquery)

## Règle documentaire

Ce fichier ne contient volontairement ni longues procédures ni commandes détaillées. Son rôle est uniquement d'expliquer l'ordre global et de rediriger vers le bon guide opérationnel.
