# Backlog Agile — DataTalent Pipeline

## Organisation

- **4 Epics** réparties entre 4 membres de l'équipe
- Chaque epic est autonome mais a des dépendances avec les autres (indiquées)
- Format des tickets : `[EPIC-ID]-[NUM] — Titre`
- Estimation en story points (fibonacci : 1, 2, 3, 5, 8, 13)

---

## EPIC 1 — Ingestion des données (Extraction & chargement raw)

**Owner** : Membre 1
**Objectif** : Extraire les données des 3 sources publiques et les charger dans la couche raw (stockage objet + entrepôt de données)
**Dépendances** : Nécessite le bucket de stockage et le dataset raw créés par l'Epic 4

### Tickets

#### ING-01 — Documenter les 3 sources de données (format, volume, fréquence, contraintes)
- **Type** : Tâche
- **Points** : 3
- **Description** : Produire un document de cartographie des 3 sources (API France Travail, Stock Sirene INSEE, API Géo). Pour chaque source : format des données, volume estimé, fréquence de mise à jour, contraintes d'accès (authentification, rate limiting, pagination), qualité apparente des données, champs clés disponibles.
- **Critères d'acceptation** :
  - Un fichier `docs/data_sources.md` est présent dans le repo
  - Les 3 sources sont documentées avec tous les critères demandés
  - Les champs de jointure entre sources sont identifiés (SIRET, code commune)
  - Les limites de qualité sont mentionnées (SIRET manquant, salaire en texte libre)

#### ING-02 — Créer le compte développeur France Travail et valider l'accès OAuth2
- **Type** : Tâche
- **Points** : 2
- **Description** : Créer un compte sur `https://francetravail.io/data/api`, enregistrer une application, obtenir les `client_id` / `client_secret`. Valider l'obtention d'un token OAuth2 via `https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=/partenaire`. Documenter le flux dans le README.
- **Critères d'acceptation** :
  - Un token est obtenu avec succès
  - Le fichier `.env.example` contient les variables `FT_CLIENT_ID` et `FT_CLIENT_SECRET`
  - Un test manuel d'appel à l'API offres retourne des résultats

#### ING-03 — Développer le script d'ingestion API France Travail
- **Type** : User Story
- **Points** : 8
- **Description** : En tant que data engineer, je veux un script Python (`src/ingestion/ingest_france_travail.py`) qui extrait les offres d'emploi Data Engineer depuis l'API France Travail et les stocke en Parquet dans le bucket raw. Le script doit :
  - Gérer l'authentification OAuth2 avec mise en cache du token (vérifier expiration avant chaque batch)
  - Filtrer par codes ROME pertinents (M1811, M1805, M1810)
  - Paginer les résultats sur les 101 départements (paramètre `range`, max 150/page)
  - Respecter le rate limiting (pause entre les requêtes, lecture des headers `X-RateLimit-*`)
  - Être idempotent (ne pas créer de doublons si relancé)
  - Journaliser les exécutions (logging Python avec horodatage, nb offres extraites, erreurs)
  - Gérer les erreurs HTTP (retry avec backoff exponentiel sur 429/5xx)
  - Écrire les résultats en Parquet partitionné par date d'extraction dans le bucket raw
- **Critères d'acceptation** :
  - Le script s'exécute sans erreur et produit des fichiers Parquet dans `raw/france_travail/`
  - L'authentification gère l'expiration du token
  - Les logs montrent le nombre d'offres extraites par département
  - Relancer le script ne crée pas de doublons

#### ING-04 — Développer le script d'ingestion Stock Sirene (INSEE)
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux un script Python (`src/ingestion/ingest_sirene.py`) qui télécharge les fichiers Parquet du stock Sirene depuis data.gouv.fr et les charge dans le bucket raw puis dans l'entrepôt de données. Le script doit :
  - Télécharger les fichiers StockUniteLegale et StockEtablissement (format Parquet)
  - Gérer le volume (plusieurs Go) avec du streaming ou du chunking
  - Vérifier l'intégrité du fichier (taille, checksum si disponible)
  - Charger les données dans le dataset raw de l'entrepôt
  - Être idempotent (écrasement ou upsert)
  - Journaliser le nombre de lignes chargées et la durée
- **Critères d'acceptation** :
  - Les fichiers Parquet sont téléchargés et stockés dans `raw/sirene/`
  - Les données sont chargées dans l'entrepôt de données (table raw)
  - Le script gère un téléchargement interrompu (retry)
  - Les logs indiquent le volume traité

#### ING-05 — Développer le script d'ingestion API Géo
- **Type** : User Story
- **Points** : 3
- **Description** : En tant que data engineer, je veux un script Python (`src/ingestion/ingest_geo.py`) qui extrait les référentiels géographiques (régions, départements, communes) depuis l'API Géo et les stocke dans le bucket raw. Le script doit :
  - Appeler les 3 endpoints : `/regions`, `/departements`, `/communes`
  - Stocker les résultats en JSON et/ou Parquet dans le bucket raw
  - Être idempotent
  - Journaliser les exécutions
- **Critères d'acceptation** :
  - Les 3 référentiels sont extraits et stockés dans `raw/geo/`
  - Le nombre de régions, départements et communes est cohérent (18 régions, 101 départements, ~35000 communes)
  - Le script est relançable sans effet de bord

#### ING-06 — Conteneuriser les scripts d'ingestion (Dockerfile)
- **Type** : Tâche
- **Points** : 3
- **Description** : Créer un `Dockerfile` et un `docker-compose.yml` pour exécuter les scripts d'ingestion dans un conteneur. Le Dockerfile doit inclure Python, les dépendances (`requirements.txt`), et permettre de lancer chaque script via une variable d'environnement ou un argument.
- **Critères d'acceptation** :
  - `docker build` réussit sans erreur
  - `docker run` avec les bonnes variables d'environnement exécute l'ingestion
  - Le `requirements.txt` est complet et versionné
  - Le `.env.example` documente toutes les variables nécessaires

#### ING-07 — Planifier l'ingestion automatique (ordonnanceur + conteneur serverless)
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux que l'ingestion s'exécute automatiquement sans intervention manuelle. Configurer un ordonnanceur cloud (Cloud Scheduler, EventBridge, ou cron Airflow) qui déclenche un conteneur serverless (Cloud Run Job, Lambda, etc.) exécutant les scripts d'ingestion selon un planning défini :
  - France Travail : quotidien (ou hebdomadaire)
  - Sirene : mensuel
  - API Géo : mensuel (ou à la demande)
- **Critères d'acceptation** :
  - Un job planifié est configuré et déclenche l'ingestion automatiquement
  - Les logs du job sont consultables dans la console cloud
  - Le job est défini en IaC (coordonner avec Epic 4)

---

## EPIC 2 — Transformation des données (dbt : staging → intermediate → marts)

**Owner** : Membre 2
**Objectif** : Modéliser les transformations SQL avec dbt en 3 couches pour produire des tables analytiques répondant à la question centrale
**Dépendances** : Nécessite les données raw chargées par l'Epic 1

### Tickets

#### DBT-01 — Initialiser le projet dbt et configurer la connexion à l'entrepôt
- **Type** : Tâche
- **Points** : 2
- **Description** : Initialiser un projet dbt-core (`dbt init`), configurer le `profiles.yml` pour se connecter à l'entrepôt de données (BigQuery/Snowflake/Redshift), organiser l'arborescence `models/staging/`, `models/intermediate/`, `models/marts/`. Configurer le `dbt_project.yml` avec les materialization par défaut (view pour staging, table pour marts).
- **Critères d'acceptation** :
  - `dbt debug` passe sans erreur
  - L'arborescence des modèles est créée
  - Le `dbt_project.yml` est configuré avec les bonnes materialization

#### DBT-02 — Modèles staging : nettoyage des offres France Travail
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux un modèle `stg_france_travail__offres.sql` qui nettoie et type les données brutes des offres. Le modèle doit :
  - Sélectionner les colonnes utiles et les renommer en snake_case
  - Typer correctement les dates (`dateCreation` → DATE)
  - Normaliser les codes communes et codes postaux
  - Extraire les informations de salaire quand disponibles (parsing du champ texte libre en salaire min/max)
  - Filtrer les offres invalides (sans intitulé, sans localisation)
  - Dédoublonner par `id` d'offre
- **Critères d'acceptation** :
  - `dbt run --select stg_france_travail__offres` s'exécute sans erreur
  - Les types sont corrects (dates, entiers, strings)
  - Un `.yml` de documentation accompagne le modèle avec description des colonnes

#### DBT-03 — Modèles staging : nettoyage du stock Sirene
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux deux modèles staging pour Sirene :
  - `stg_sirene__unites_legales.sql` : unités légales (entreprises) avec siren, dénomination, catégorie juridique, code NAF, tranche effectifs
  - `stg_sirene__etablissements.sql` : établissements avec siret, siren, code commune, code postal, état administratif
  - Filtrer sur `etatAdministratifEtablissement = 'A'` (actifs uniquement)
  - Renommer et typer les colonnes
- **Critères d'acceptation** :
  - Les 2 modèles s'exécutent sans erreur
  - Seuls les établissements actifs sont conservés
  - Documentation `.yml` présente

#### DBT-04 — Modèles staging : nettoyage des référentiels géographiques
- **Type** : User Story
- **Points** : 3
- **Description** : En tant que data engineer, je veux trois modèles staging pour les données géo :
  - `stg_geo__regions.sql`
  - `stg_geo__departements.sql`
  - `stg_geo__communes.sql`
  - Renommer les colonnes, typer, extraire latitude/longitude depuis le champ `centre`
- **Critères d'acceptation** :
  - Les 3 modèles s'exécutent sans erreur
  - Les coordonnées sont extraites en colonnes latitude/longitude
  - Documentation `.yml` présente

#### DBT-05 — Modèle intermediate : jointure offres × entreprises Sirene
- **Type** : User Story
- **Points** : 8
- **Description** : En tant que data engineer, je veux un modèle `int_offres_enrichies.sql` qui joint les offres France Travail aux entreprises Sirene pour enrichir chaque offre avec les informations entreprise (dénomination officielle, code NAF, catégorie juridique, tranche effectifs). La jointure se fait sur le SIRET quand disponible. Gérer les cas où le SIRET est absent (LEFT JOIN, indicateur `has_siret_match`).
- **Critères d'acceptation** :
  - Le modèle s'exécute sans erreur
  - Les offres avec SIRET sont enrichies des infos Sirene
  - Un indicateur `has_siret_match` permet d'identifier le taux de jointure
  - Documentation `.yml` présente

#### DBT-06 — Modèle intermediate : enrichissement géographique
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux un modèle `int_offres_geo.sql` qui enrichit les offres avec les données géographiques (nom commune, département, région, coordonnées). Jointure via le code commune INSEE entre les offres et le référentiel communes, puis enrichissement département et région.
- **Critères d'acceptation** :
  - Chaque offre est enrichie du nom de commune, département, région
  - Les coordonnées GPS sont disponibles pour la cartographie
  - Le taux de matching géographique est documenté

#### DBT-07 — Modèles marts : agrégats analytiques pour le dashboard
- **Type** : User Story
- **Points** : 8
- **Description** : En tant que data engineer, je veux des modèles marts prêts pour le dashboard :
  - `mart_offres_par_departement.sql` : nombre d'offres, salaire moyen/médian par département
  - `mart_offres_par_secteur.sql` : nombre d'offres par code NAF / libellé secteur
  - `mart_offres_par_mois.sql` : évolution temporelle du nombre d'offres et des salaires
  - `mart_offres_detail.sql` : table de détail avec toutes les dimensions pour le filtrage dans le dashboard
  - Utiliser le partitionnement et le clustering sur les champs clés (date, département, code NAF)
  - Activer `require_partition_filter: true` sur les tables Sirene pour bloquer les full-scans accidentels (10M+ lignes = ~0,05$/To)
- **Critères d'acceptation** :
  - Les 4 modèles s'exécutent sans erreur
  - Les agrégats sont cohérents (pas de doublons, totaux vérifiables)
  - Le partitionnement/clustering est configuré dans `dbt_project.yml` ou dans les config des modèles avec `require_partition_filter: true` sur les modèles Sirene
  - Documentation `.yml` complète

#### DBT-08 — Tests de qualité dbt (not_null, unique, accepted_values, relationships)
- **Type** : Tâche
- **Points** : 5
- **Description** : Définir des tests de qualité dbt sur les champs critiques de chaque couche :
  - `not_null` sur les clés primaires et champs obligatoires
  - `unique` sur les identifiants (id offre, siret, code commune)
  - `accepted_values` sur les champs à valeurs finies (type contrat, état administratif)
  - `relationships` entre les modèles (FK offres → communes, offres → entreprises)
  - Tests custom si nécessaire (ex : salaire min ≤ salaire max)
- **Critères d'acceptation** :
  - `dbt test` passe sans échec
  - Au moins 15 tests sont définis
  - Les tests couvrent les 3 couches (staging, intermediate, marts)

#### DBT-09 — Documentation dbt et lignage
- **Type** : Tâche
- **Points** : 3
- **Description** : Documenter tous les modèles dans les fichiers `.yml` (description des modèles et colonnes). Générer la documentation dbt (`dbt docs generate`) et vérifier que le lignage (DAG) est visible et cohérent. Ajouter des descriptions sur les sources dans un fichier `sources.yml`.
- **Critères d'acceptation** :
  - `dbt docs generate` s'exécute sans erreur
  - Tous les modèles et colonnes critiques ont une description
  - Le DAG de lignage montre le flux raw → staging → intermediate → marts
  - Les sources sont déclarées et documentées

---

## EPIC 3 — Dashboard analytique et gouvernance des données

**Owner** : Membre 3
**Objectif** : Produire les tableaux de bord (analytique + coûts) et documenter le catalogue de données
**Dépendances** : Nécessite les tables marts de l'Epic 2

### Tickets

#### DASH-01 — Choisir et configurer l'outil de BI
- **Type** : Tâche
- **Points** : 2
- **Description** : Connecter **Looker Studio** (recommandé) au dataset `marts` de BigQuery. Looker Studio est natif GCP, gratuit, connecté directement à BigQuery sans couche intermédiaire. Évite de provisionner un serveur Metabase ou Superset (Cloud Run ou VM en continu = coût fixe mensuel non justifié). Documenter la configuration dans le README. L'outil doit permettre un accès public au dashboard (lien partageable).
- **Choix recommandé** : Looker Studio (gratuit, natif GCP, connecteur BigQuery natif, lien public intégré)
- **Alternative** : Metabase Cloud ou Superset si visualisations avancées nécessaires (coût ~10-20€/mois supplémentaire)
- **Critères d'acceptation** :
  - L'outil est connecté à BigQuery et affiche les données marts
  - Un lien public est générable
  - Le choix est justifié dans le README

#### DASH-02 — Dashboard analytique : vue géographique
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que membre de l'équipe produit, je veux visualiser la répartition géographique des offres Data Engineer en France. Créer une page/onglet avec :
  - Carte de France (choroplèthe) colorée par nombre d'offres par département ou région
  - Classement des top 10 départements/régions par nombre d'offres
  - Filtre par période temporelle
  - KPI : nombre total d'offres, nombre de départements couverts
- **Critères d'acceptation** :
  - La carte est lisible et interactive (tooltip au survol)
  - Les filtres fonctionnent
  - Les données sont cohérentes avec les marts

#### DASH-03 — Dashboard analytique : vue sectorielle
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que membre de l'équipe produit, je veux visualiser la répartition des offres par secteur d'activité et type d'entreprise. Créer une page/onglet avec :
  - Graphique en barres des top secteurs (code NAF / libellé) recrutant des Data Engineers
  - Répartition par type de contrat (CDI, CDD, freelance, alternance)
  - Répartition par taille d'entreprise (tranche effectifs)
  - Filtre par région/département
- **Critères d'acceptation** :
  - Les graphiques sont lisibles et interactifs
  - Les filtres croisés fonctionnent (secteur × géographie)
  - Les libellés NAF sont compréhensibles (pas juste les codes)

#### DASH-04 — Dashboard analytique : vue temporelle et salaires
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que membre de l'équipe produit, je veux visualiser l'évolution temporelle des offres et des salaires. Créer une page/onglet avec :
  - Courbe d'évolution du nombre d'offres par mois
  - Distribution des salaires proposés (histogramme ou box plot)
  - Salaire médian par région et par secteur
  - Filtre par type de contrat, région, secteur
- **Critères d'acceptation** :
  - Les tendances temporelles sont visibles
  - Les salaires sont affichés de manière compréhensible (annuel brut)
  - Les filtres fonctionnent

#### DASH-05 — Dashboard de suivi des coûts cloud
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que CTO, je veux un tableau de bord de suivi des coûts cloud. Créer un dashboard (ou une page dédiée) avec :
  - Coût par service (stockage, compute, entrepôt de données, ordonnanceur)
  - Évolution des coûts dans le temps (jour/semaine/mois)
  - Alertes visuelles sur les dépassements de budget
  - Estimation mensuelle projetée
- **Critères d'acceptation** :
  - Les coûts par service sont visibles
  - Une alerte est configurée (ou simulée) pour les dépassements
  - Le dashboard est documenté

#### DASH-06 — Créer le catalogue de données (descriptions, propriétaires, tags)
- **Type** : Tâche
- **Points** : 5
- **Description** : Produire un catalogue documentant toutes les tables marts :
  - Description de chaque table et de ses colonnes
  - Source(s) d'origine et fréquence de mise à jour
  - Propriétaire (owner) de chaque table
  - Tags de sensibilité (données personnelles, données publiques)
  - Format : document Markdown (`docs/data_catalog.md`) ou intégration dans dbt docs
- **Critères d'acceptation** :
  - Toutes les tables marts sont documentées
  - Les sources et fréquences sont indiquées
  - Les données sensibles (SIRET, noms d'entreprise) sont identifiées et taguées
  - Le catalogue est accessible (dans le repo ou via dbt docs)

#### DASH-07 — Produire le schéma d'architecture
- **Type** : Tâche
- **Points** : 3
- **Description** : Créer un schéma d'architecture (draw.io, Excalidraw, ou image) représentant le flux complet de données de l'ingestion au dashboard. Le schéma doit montrer :
  - Les 3 sources de données
  - Le pipeline d'ingestion (scripts Python, conteneur)
  - Le stockage objet (raw)
  - L'entrepôt de données (raw, staging, marts)
  - dbt (transformations)
  - L'ordonnanceur
  - Le dashboard
  - Le pipeline CI/CD
- **Critères d'acceptation** :
  - Le schéma est lisible et complet
  - Tous les composants cloud sont représentés
  - Le schéma est inclus dans le README (image ou lien draw.io)

#### DASH-08 — Rédiger le README complet du projet
- **Type** : Tâche
- **Points** : 3
- **Description** : Rédiger le README du repo GitHub avec :
  - Description du projet et question centrale
  - Schéma d'architecture
  - Fournisseur cloud choisi et justification
  - Stack technologique
  - Instructions de déploiement (prérequis, variables d'environnement, commandes)
  - Liens vers le dashboard et le Kanban
  - Auteurs
- **Critères d'acceptation** :
  - Le README est complet et bien structuré
  - Un nouveau contributeur peut comprendre le projet et le déployer
  - Les liens sont fonctionnels

---

## EPIC 4 — Infrastructure as Code, CI/CD et DevOps

**Owner** : Membre 4
**Objectif** : Provisionner toute l'infrastructure cloud via IaC, configurer le pipeline CI/CD, et estimer les coûts
**Dépendances** : Toutes les autres epics dépendent de l'infra (bucket, entrepôt, secrets)

### Tickets

#### INFRA-01 — Choisir le fournisseur cloud et créer l'espace de travail
- **Type** : Tâche
- **Points** : 2
- **Description** : Choisir le fournisseur cloud (GCP, AWS, Azure) et créer le projet/compte. Documenter le choix et la justification (coût, services disponibles, free tier). Créer les premiers accès (compte de service, clés API).
- **Critères d'acceptation** :
  - Le projet cloud est créé
  - Un compte de service avec les permissions nécessaires est configuré
  - Le choix est justifié dans le README

#### INFRA-02 — Module IaC : stockage objet (bucket raw)
- **Type** : User Story
- **Points** : 3
- **Description** : En tant que data engineer, je veux un module Terraform/OpenTofu (`infra/modules/storage/`) qui provisionne un bucket de stockage objet pour les données raw. Le module doit :
  - Créer le bucket avec un nommage conventionnel
  - Configurer le versioning (optionnel)
  - Configurer une politique de lifecycle (suppression après X jours pour les données temporaires)
  - Paramétrer la région et les accès (IAM)
- **Critères d'acceptation** :
  - `tofu apply` (ou `terraform apply`) crée le bucket sans erreur
  - Le bucket est accessible par le compte de service
  - Le module est paramétrable (nom, région, lifecycle)

#### INFRA-03 — Module IaC : entrepôt de données (datasets raw/staging/marts)
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux un module Terraform/OpenTofu (`infra/modules/warehouse/`) qui provisionne l'entrepôt de données avec les datasets/schemas nécessaires :
  - Dataset `raw` : données brutes
  - Dataset `staging` : données nettoyées
  - Dataset `marts` : données agrégées
  - Configurer les permissions d'accès par dataset
  - Configurer le partitionnement et le clustering si applicable
- **Critères d'acceptation** :
  - Les 3 datasets sont créés
  - Les permissions sont configurées (read-only pour le dashboard, read-write pour dbt)
  - Le module est paramétrable

#### INFRA-04 — Module IaC : conteneur serverless (Cloud Run / Lambda)
- **Type** : User Story
- **Points** : 5
- **Description** : En tant que data engineer, je veux un module Terraform/OpenTofu (`infra/modules/compute/`) qui provisionne un service de conteneur serverless pour exécuter les scripts d'ingestion. Le module doit :
  - Créer le service (Cloud Run Job, Lambda, Container App)
  - Configurer les variables d'environnement et secrets
  - Configurer les limites de ressources (mémoire, CPU, timeout)
  - Configurer le compte de service et les permissions
- **Critères d'acceptation** :
  - Le service est créé et peut exécuter le conteneur Docker
  - Les secrets sont injectés via Secret Manager (pas en clair)
  - Le module est paramétrable (image, mémoire, timeout)

#### INFRA-05 — Module IaC : ordonnanceur (Cloud Scheduler / EventBridge)
- **Type** : User Story
- **Points** : 3
- **Description** : En tant que data engineer, je veux un module Terraform/OpenTofu (`infra/modules/scheduler/`) qui provisionne l'ordonnanceur cloud pour déclencher les jobs d'ingestion selon un planning cron :
  - France Travail : `0 6 * * *` (quotidien 6h) ou `0 6 * * 1` (hebdo lundi)
  - Sirene : `0 3 1 * *` (mensuel 1er du mois)
  - API Géo : `0 4 1 * *` (mensuel)
- **Critères d'acceptation** :
  - Les jobs planifiés sont créés
  - Les expressions cron sont correctes
  - Le module est paramétrable (schedule, target)

#### INFRA-06 — Module IaC : gestion des secrets (Secret Manager)
- **Type** : User Story
- **Points** : 3
- **Description** : En tant que data engineer, je veux un module Terraform/OpenTofu (`infra/modules/secrets/`) qui provisionne le gestionnaire de secrets cloud et y stocke les credentials nécessaires :
  - `FT_CLIENT_ID` et `FT_CLIENT_SECRET` (France Travail)
  - Credentials de l'entrepôt de données
  - Tout autre secret nécessaire
  - Les secrets ne doivent jamais apparaître dans le code IaC (utiliser `terraform.tfvars` non versionné ou variables d'environnement)
- **Critères d'acceptation** :
  - Les secrets sont créés dans Secret Manager
  - Le code IaC ne contient aucun secret en clair
  - Le `.gitignore` exclut les fichiers sensibles (`.tfvars`, `.env`)

#### INFRA-07 — Module IaC : gestion des accès (IAM)
- **Type** : Tâche
- **Points** : 3
- **Description** : Configurer les rôles et permissions IAM via IaC :
  - Compte de service pour l'ingestion (accès bucket + entrepôt en écriture)
  - Compte de service pour dbt (accès entrepôt en lecture/écriture)
  - Compte de service pour le dashboard (accès marts en lecture seule)
  - Principe du moindre privilège
- **Critères d'acceptation** :
  - Les comptes de service sont créés avec les bonnes permissions
  - Aucun compte n'a plus de droits que nécessaire
  - La configuration est dans l'IaC

#### INFRA-08 — Estimer et documenter les coûts d'infrastructure
- **Type** : Tâche
- **Points** : 3
- **Description** : Utiliser Infracost ou l'estimateur du fournisseur cloud pour estimer les coûts mensuels de l'infrastructure. Documenter :
  - Coût par service (stockage, compute, entrepôt, ordonnanceur, secrets)
  - Identification des postes les plus coûteux
  - Leviers d'optimisation (requêtes ciblées, partitionnement, mise en veille, free tier)
  - Estimation mensuelle totale
- **Critères d'acceptation** :
  - Un document `docs/cost_estimation.md` est produit
  - Les coûts sont détaillés par service
  - Les optimisations sont justifiées
  - Si Infracost est utilisé, le fichier de sortie est inclus dans le repo

#### INFRA-09 — Configurer le pipeline CI/CD (GitHub Actions)
- **Type** : User Story
- **Points** : 8
- **Description** : En tant que data engineer, je veux un pipeline CI/CD via GitHub Actions qui assure la qualité du code à chaque changement. Configurer :
  - **Sur PR** :
    - Lint Python (ruff ou flake8)
    - Compilation SQL dbt (`dbt compile` ou `dbt parse`)
    - Validation IaC (`tofu validate` / `terraform validate` + `tofu fmt --check`)
  - **Sur merge main** :
    - Déploiement automatique de l'infrastructure (`tofu apply`)
    - Exécution de `dbt run` + `dbt test`
  - **Jobs planifiés** (optionnel) :
    - Déclenchement de l'ingestion via workflow dispatch ou cron GitHub Actions
- **Critères d'acceptation** :
  - Les workflows `.github/workflows/` sont créés
  - Une PR déclenche les validations (lint, compile, validate)
  - Un merge sur main déclenche le déploiement
  - Les secrets GitHub sont configurés (pas de credentials dans le code)

#### INFRA-10 — Configurer le repo GitHub (structure, .gitignore, branch protection)
- **Type** : Tâche
- **Points** : 2
- **Description** : Configurer le repo GitHub avec :
  - Structure de dossiers : `src/ingestion/`, `models/`, `infra/`, `docs/`, `.github/workflows/`
  - `.gitignore` complet (`.env`, `.tfvars`, `target/`, `__pycache__/`, `*.pyc`, `.terraform/`)
  - Branch protection sur `main` (require PR, require CI pass)
  - `.env.example` avec toutes les variables documentées
- **Critères d'acceptation** :
  - La structure est en place
  - Le `.gitignore` est complet
  - Les push directs sur main sont bloqués

---

## Résumé des Epics

| Epic | Owner | Nb tickets | Points totaux | Périmètre |
|------|-------|-----------|---------------|-----------|
| EPIC 1 — Ingestion | Membre 1 | 7 | 29 | Extraction des 3 sources, chargement raw, conteneurisation, planification |
| EPIC 2 — Transformation | Membre 2 | 9 | 44 | dbt staging/intermediate/marts, tests qualité, documentation lignage |
| EPIC 3 — Dashboard & Gouvernance | Membre 3 | 8 | 33 | Dashboard analytique + coûts, catalogue, schéma d'archi, README |
| EPIC 4 — Infra & CI/CD | Membre 4 | 10 | 37 | IaC modules, estimation coûts, CI/CD, config repo |

## Dépendances inter-epics

```
EPIC 4 (Infra) ──► EPIC 1 (Ingestion) ──► EPIC 2 (Transformation) ──► EPIC 3 (Dashboard)
   │                                              │
   └──────────────── CI/CD couvre tout ───────────┘
```

- **EPIC 4 doit démarrer en premier** (au moins INFRA-01, INFRA-02, INFRA-03) pour débloquer les autres
- **EPIC 1** peut commencer dès que le bucket et l'entrepôt sont prêts (ING-01/02 en parallèle)
- **EPIC 2** démarre dès que les premières données raw sont chargées
- **EPIC 3** démarre dès que les premiers marts sont disponibles (DASH-07/08 peuvent être faits en parallèle)
- **INFRA-09** (CI/CD) est transverse et peut être itéré tout au long du projet

## Sprints suggérés (15 jours)

| Sprint | Jours | Focus |
|--------|-------|-------|
| Sprint 1 | J1-J5 | Cadrage (toutes epics), infra de base (EPIC 4), premiers scripts ingestion (EPIC 1), init dbt (EPIC 2) |
| Sprint 2 | J6-J10 | Fin ingestion (EPIC 1), transformations dbt complètes (EPIC 2), modules IaC restants (EPIC 4), début dashboard (EPIC 3) |
| Sprint 3 | J11-J15 | Dashboard complet (EPIC 3), CI/CD (EPIC 4), tests et docs (EPIC 2), coûts et gouvernance (EPIC 3/4), démo |
