# Architecture du Projet

Ce document présente l'architecture technique du pipeline de données pour la cartographie du marché Data Engineer en France.

## Schéma Global

```mermaid
graph TD
    %% Sources groupées par fréquence
    subgraph SOURCES ["Sources Externes (APIs)"]
        subgraph WEEKLY_SRC ["Hebdomadaire"]
            FT[France Travail]
            APEC[APEC]
            JB[Jooble]
        end
        subgraph MONTHLY_SRC ["Mensuel"]
            SIR[INSEE Sirene]
            GEO[API Geo]
        end
    end

    %% Ingestion
    subgraph INGESTION ["GCP - Ingestion"]
        CS_W[Scheduler: Weekly]
        CS_M[Scheduler: Monthly]
        CR_ING[Cloud Run Job: Ingestion]
        SM[Secret Manager]
    end

    %% Flux Ingestion
    WEEKLY_SRC --> |Extraction| CR_ING
    MONTHLY_SRC --> |Extraction| CR_ING
    
    CS_W --> |Trigger| CR_ING
    CS_M --> |Trigger| CR_ING
    CR_ING -.-> |Read Secrets| SM

    %% Stockage
    subgraph STORAGE ["GCP - Storage (Data Lake)"]
        GCS[(Cloud Storage: Raw Parquet)]
    end

    CR_ING --> |Upload| GCS

    %% Entrepôt
    subgraph WAREHOUSE ["GCP - Data Warehouse (BigQuery)"]
        direction TB
        BQ_RAW[Dataset: raw]
        BQ_STG[Dataset: staging]
        BQ_INT[Dataset: intermediate]
        BQ_MRT[Dataset: marts]

        BQ_RAW --> BQ_STG --> BQ_INT --> BQ_MRT
    end

    GCS -.-> |External Tables| BQ_RAW

    %% Transformation
    subgraph TRANSFORM ["GCP - Transformation"]
        CS_DBT[Scheduler: dbt]
        CR_DBT[Cloud Run Job: dbt]
        DBT_P[dbt Pipeline: stg > int > mart]
    end

    CS_DBT --> |Trigger| CR_DBT
    CR_DBT --> |Execute| DBT_P
    DBT_P ==> |Orchestrate SQL| BQ_STG
    DBT_P ==> |Orchestrate SQL| BQ_INT
    DBT_P ==> |Orchestrate SQL| BQ_MRT

    %% Visualisation
    subgraph VISUAL ["Visualisation"]
        LS[Looker Studio: Dashboard]
    end

    BQ_MRT --> |Query| LS
    DBT_P -.-> |Refresh Data| LS

    %% DevOps (CI/CD)
    subgraph DEVOPS ["DevOps / CI-CD"]
        GH[GitHub Actions]
        TF[Terraform]
        AR[Artifact Registry]
    end

    GH --> |IaC| TF
    GH --> |Build & Push| AR
    AR -.-> |Images| CR_ING
    AR -.-> |Images| CR_DBT

    %% Styles
    style BQ_MRT fill:#f96,stroke:#333,stroke-width:2px
    style LS fill:#4285F4,color:#fff
    style CR_ING fill:#6baed6,color:#fff
    style CR_DBT fill:#6baed6,color:#fff
```

## Description des Composants

### 1. Ingestion
Les scripts Python (`src/ingestion/`) sont encapsulés dans des conteneurs Docker et exécutés comme des **Cloud Run Jobs**.
- **Flux Hebdomadaire (Lundi)** : Récupération des offres d'emploi pour France Travail, APEC et Jooble.
- **Flux Mensuel (1er du mois)** : Mise à jour des référentiels Sirene et Geo.

### 2. Stockage (Data Lake)
Les données sont persistées sur **Google Cloud Storage** au format **Parquet**. Le partitionnement est de type Hive : `dt=YYYY-MM-DD`.

### 3. Transformation (ELT)
Le projet utilise **dbt** pour transformer les données directement au sein de **BigQuery**.
- **raw** : Tables externes sur GCS.
- **staging** : Nettoyage technique.
- **intermediate** : Logique métier (jointures, enrichissement géographique).
- **marts** : Vues prêtes pour la consommation.

### 4. Orchestration
**Cloud Scheduler** gère le planning :
- **Ingestion Weekly** : Lundi matin pour les offres d'emploi.
- **Ingestion Monthly** : 1er du mois pour les entreprises et la géographie.
- **Job dbt** : Exécuté après les ingestions pour mettre à jour les tableaux de bord.

### 5. Infrastructure
L'ensemble de l'infrastructure est défini par du code (**Terraform**) situé dans le dossier `infra/`.
