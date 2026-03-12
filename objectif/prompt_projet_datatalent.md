# Prompt Projet — DataTalent : Pipeline Data Engineering Marché de l'Emploi

## Contexte général

DataTalent est une startup spécialisée dans l'analyse du marché de l'emploi tech. Son équipe produit publie des rapports trimestriels à destination des candidats et recruteurs dans la data. Actuellement, la collecte et le traitement des données sont entièrement manuels : un analyste télécharge chaque semaine des fichiers depuis plusieurs sites, les consolide dans des tableurs et produit des graphiques à la main. Ce processus est long, fragile et non reproductible.

Le CTO a décidé d'industrialiser ce processus. L'objectif est de concevoir et construire une infrastructure data complète sur un fournisseur cloud, capable d'ingérer automatiquement les données, de les transformer en données analytiques fiables, et de les restituer dans un tableau de bord accessible à l'équipe produit.

## Question centrale

> **"Où recrute-t-on des Data Engineers en France, dans quelles entreprises et à quels salaires ?"**

Le pipeline doit permettre de répondre à cette question selon au moins trois angles d'analyse : géographique (par région/département), sectoriel (par code NAF / secteur d'activité) et temporel (évolution dans le temps).

## Sources de données

### 1. API France Travail (ex Pôle Emploi)

- **URL** : `https://api.francetravail.io/partenaire/offresdemploi/v2/offres/search`
- **Nature** : Offres d'emploi publiées en temps réel sur l'ensemble du territoire français
- **Authentification** : OAuth2 (client credentials) — nécessite un compte développeur sur `https://francetravail.io/data/api`
- **Filtrage** : Par codes ROME (ex : M1811 — Data Engineer, M1805 — Études et développement informatique) et par département (01 à 95 + DOM-TOM)
- **Pagination** : Résultats paginés (max 150 par page), paramètres `range` (ex : `0-149`)
- **Rate limiting** : Respecter les quotas de l'API (vérifier headers `X-RateLimit-*`)
- **Volume estimé** : Variable selon les périodes, quelques centaines à quelques milliers d'offres actives pour les métiers data
- **Fréquence de mise à jour** : Temps réel (nouvelles offres ajoutées en continu)
- **Champs clés** : `id`, `intitule`, `description`, `dateCreation`, `lieuTravail.codePostal`, `lieuTravail.commune`, `entreprise.nom`, `entreprise.numeroSiret` (quand disponible), `salaire.libelle`, `salaire.complement1`, `typeContrat`, `codeROME`, `appellationlibelle`
- **Contraintes** : Le champ SIRET n'est pas toujours renseigné. Le salaire est souvent en texte libre, parfois absent.

### 2. Stock Sirene — INSEE

- **URL** : `https://www.data.gouv.fr/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/`
- **Nature** : Registre national des entreprises et établissements français
- **Format** : Fichiers Parquet (StockUniteLegale et StockEtablissement), mis à jour mensuellement
- **Volume estimé** : Plusieurs gigaoctets (StockEtablissement > 10 millions de lignes)
- **Fréquence de mise à jour** : Mensuelle (1er de chaque mois environ)
- **Champs clés** : `siren`, `siret`, `denominationUniteLegale`, `categorieJuridiqueUniteLegale`, `activitePrincipaleUniteLegale` (code NAF), `trancheEffectifsUniteLegale`, `codeCommuneEtablissement`, `codePostalEtablissement`, `etatAdministratifEtablissement`
- **Contraintes** : Volume conséquent nécessitant un chargement optimisé. Beaucoup d'établissements fermés à filtrer (`etatAdministratifEtablissement = 'A'` pour actifs).

### 3. API Géo — Gouvernement

- **URL** : `https://geo.api.gouv.fr`
- **Nature** : Référentiels officiels des régions, départements et communes françaises
- **Authentification** : Aucune (accès libre)
- **Endpoints utiles** :
  - `/regions` — Liste des régions avec codes et noms
  - `/departements` — Liste des départements avec codes, noms et code région
  - `/communes` — Liste des communes avec codes INSEE, noms, codes postaux, coordonnées, population
- **Volume estimé** : Faible (quelques dizaines de Ko à quelques Mo)
- **Fréquence de mise à jour** : Annuelle (COG — Code Officiel Géographique)
- **Champs clés** : `code` (code INSEE), `nom`, `codeRegion`, `codeDepartement`, `codesPostaux`, `population`, `centre.coordinates` (latitude/longitude)
- **Contraintes** : Aucune contrainte majeure. Données stables et fiables.

## Jointures entre sources

Le lien principal entre les offres France Travail et le registre Sirene se fait via le **SIRET** :
- `entreprise.numeroSiret` (France Travail) → `siret` (Sirene)
- Ce champ n'étant pas toujours renseigné dans les offres, une jointure secondaire peut être tentée via le **nom d'entreprise** (fuzzy matching) combiné au **code postal** ou **code commune**.

Le lien géographique se fait via le **code commune INSEE** :
- `lieuTravail.commune` (France Travail) → `code` (API Géo)
- `codeCommuneEtablissement` (Sirene) → `code` (API Géo)

## Architecture cible

### Pattern Medallion — 3 couches

1. **Raw (Bronze)** : Données brutes telles qu'extraites des sources. Stockées en Parquet/JSON dans un bucket de stockage objet (ex : GCS, S3). Aucune transformation appliquée. Sert de source de vérité historique.

2. **Staging (Silver)** : Données nettoyées et typées, modélisées par source dans dbt. Nettoyage des types, renommage des colonnes, filtrage des enregistrements invalides, dédoublonnage.

3. **Marts (Gold)** : Données agrégées et croisées, prêtes pour la consommation analytique. Jointures entre offres et entreprises, enrichissement géographique, agrégats par département/région/secteur/période. Tables directement consommables par le dashboard.

### Stack technologique attendue

- **Cloud provider** : Au choix (GCP recommandé pour BigQuery, mais AWS ou Azure acceptés)
- **Stockage objet** : GCS / S3 / Azure Blob
- **Entrepôt de données** : BigQuery / Snowflake / Redshift
- **Transformation** : dbt-core (SQL)
- **Ingestion** : Scripts Python (requests, pandas, pyarrow)
- **IaC** : OpenTofu ou Terraform
- **Orchestration** : Cloud Scheduler + Cloud Run / Airflow / équivalent
- **CI/CD** : GitHub Actions
- **Dashboard** : Looker Studio / Metabase / Superset / Power BI
- **Conteneurisation** : Docker / docker-compose
- **Estimation de coûts** : Infracost ou estimateur cloud natif

### Infrastructure as Code

L'ensemble de l'infrastructure cloud doit être provisionné via IaC (OpenTofu/Terraform) :
- Bucket de stockage objet (raw data)
- Entrepôt de données (datasets/schemas pour raw, staging, marts)
- Conteneur serverless (Cloud Run / Lambda / Container App)
- Ordonnanceur (Cloud Scheduler / EventBridge)
- Gestion des accès (IAM, service accounts)
- Gestionnaire de secrets (Secret Manager / SSM)

Les modules doivent être organisés de manière réutilisable.

### CI/CD

Pipeline minimum :
- Sur PR : lint Python (ruff/flake8), compilation SQL dbt (`dbt compile`), validation IaC (`tofu validate` / `terraform validate`)
- Sur merge main : déploiement automatique de l'infrastructure et des transformations
- Jobs planifiés : ingestion automatique selon la fréquence définie

## Tableau de bord analytique

Le dashboard doit répondre à la question centrale avec au minimum :

1. **Vue géographique** : Carte ou classement des départements/régions par nombre d'offres Data Engineer
2. **Vue sectorielle** : Répartition des offres par secteur d'activité (code NAF) et par type d'entreprise
3. **Vue temporelle** : Évolution du nombre d'offres et des salaires proposés dans le temps
4. **Vue salaires** : Distribution des salaires par région, secteur, type de contrat

Un second tableau de bord de suivi des coûts cloud doit également être produit.

## Gouvernance et documentation

- Catalogue de données : descriptions des tables, propriétaires, fréquences de mise à jour
- Lignage des données visible (dbt docs ou outil équivalent)
- Tags de sensibilité sur les données
- README complet dans le repo GitHub

## Livrables attendus

1. Repo GitHub public avec : scripts Python, modèles dbt, modules IaC, CI/CD, Dockerfile, README
2. Dashboard analytique accessible publiquement
3. Dashboard de suivi des coûts cloud
4. Documentation du catalogue de données
5. Schéma d'architecture (draw.io ou image)
6. Tableau Kanban (Trello) accessible publiquement

## Contraintes techniques

- Les scripts d'ingestion doivent être **idempotents** (relançables sans effet de bord)
- Les secrets ne doivent **jamais** apparaître dans le code (`.env`, Secret Manager)
- Le pipeline dbt doit s'exécuter **sans erreur de bout en bout**
- Les requêtes doivent exploiter le **partitionnement et le clustering** de l'entrepôt
- Aucune ressource cloud ne doit être créée manuellement (tout via IaC)

## Planning indicatif

| Phase | Jours | Contenu |
|-------|-------|---------|
| 1 — Cadrage & ingestion initiale | J1-J2 | Kanban, documentation sources, choix cloud, première ingestion manuelle |
| 2 — Automatisation extraction | J3-J5 | Scripts Python pour les 3 sources, OAuth2, pagination, gestion erreurs |
| 3 — Transformation dbt | J6-J9 | Modèles staging/intermediate/marts, tests qualité, documentation lignage |
| 4 — IaC, coûts & CI/CD | J10-J12 | Modules Terraform/OpenTofu, estimation coûts, pipeline GitHub Actions |
| 5 — Dashboard & gouvernance | J13-J15 | Dashboard analytique + coûts, catalogue de données, préparation démo |
