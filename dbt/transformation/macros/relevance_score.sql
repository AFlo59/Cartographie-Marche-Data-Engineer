{#
  Macro SQL — score de pertinence Data Engineering.
  Retourne INT64 (peut être négatif pour les rôles hors cible).
  Score interprétation : >= 15 = HIGH, >= 5 = MEDIUM, > 0 = LOW, <= 0 = NOT_RELEVANT

  Usage :
    {{ relevance_score_data_eng('intitule', 'description') }}
    {{ matching_confidence_data_eng('relevance_score') }}

  Logique :
    +15 : "data engineer" / "ingénieur données" dans le titre
    + 3 : "data" seul dans le titre (scientist, analyst, architect…)
    + 4 : stack DE dans la description (Spark, Kafka, Airflow, dbt, etc.)
    + 2 : langages de base (Python, SQL, Scala…)
    + 2 : cloud plateformes (GCP, AWS, Azure…)
    -20 : métiers sans rapport (technicien, comptable, commercial…)
    - 5 : management/product sans data
#}
{% macro relevance_score_data_eng(intitule_expr, description_expr) %}
(
    -- Signal fort : intitulé explicite Data Engineer
    CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE({{ intitule_expr }}, '')),
        r'data engineer|data eng\b|ing[eé]nieur.{0,15}donn[eé]es?|ing[eé]nieur data|data pipeline|data platform'
    ) THEN 15 ELSE 0 END

    -- Signal modéré : "data" dans le titre sans "engineer"
  + CASE
        WHEN NOT REGEXP_CONTAINS(LOWER(COALESCE({{ intitule_expr }}, '')),
            r'data engineer|ing[eé]nieur data|data pipeline|data platform')
          AND REGEXP_CONTAINS(LOWER(COALESCE({{ intitule_expr }}, '')),
            r'\bdata\b|\bdonn[eé]es?\b|\banalytics?\b')
        THEN 3
        ELSE 0
    END

    -- Stack Data Engineering dans la description
  + CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE({{ description_expr }}, '')),
        r'\b(spark|pyspark|kafka|airflow|dbt|bigquery|snowflake|databricks|hadoop|hive|flink|redshift|synapse|dataflow|apache beam|luigi|prefect|dagster|dask|talend|informatica|nifi|fivetran|stitch|glue|athena|trino|presto)\b'
    ) THEN 4 ELSE 0 END

    -- Langages / SQL
  + CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE({{ description_expr }}, '')),
        r'\b(python|scala|sql|spark sql|hive ?ql|t-sql|pl.sql|pyspark|java)\b'
    ) THEN 2 ELSE 0 END

    -- Cloud plateformes
  + CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE({{ description_expr }}, '')),
        r'\b(gcp|google cloud|aws|azure|cloud storage|amazon s3|\bgcs\b|blob storage|cloud run|cloud functions?|lambda|emr|dataproc)\b'
    ) THEN 2 ELSE 0 END

    -- Pénalité forte : métiers sans rapport avec la data
  - CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE({{ intitule_expr }}, '')),
        r'technicien|technicienne|maintenance|r[eé]seaux?|s[eé]curit[eé] (informatique|r[eé]seau)|cybers[eé]curit[eé]|helpdesk|support (technique|informatique)|comptable|commercial(e)?|vendeur|vendeuse|gestionnaire de stock|logistique|supply chain|conducteur|chauffeur|infirmier|aide.soignant|m[eé]canicien|[eé]lectricien|plombier|ma[çc]on|menuisier|serveur|serveuse|agent de s[eé]curit[eé]'
    ) THEN 20 ELSE 0 END

    -- Pénalité légère : management / product sans data dans le titre
  - CASE
        WHEN REGEXP_CONTAINS(
            LOWER(COALESCE({{ intitule_expr }}, '')),
            r'scrum master|product owner|chef de projet|directeur|responsable|manager'
        )
        AND NOT REGEXP_CONTAINS(
            LOWER(COALESCE({{ intitule_expr }}, '')),
            r'\bdata\b|\bdonn[eé]es?\b'
        )
        THEN 5
        ELSE 0
    END
)
{% endmacro %}


{% macro matching_confidence_data_eng(score_expr) %}
CASE
    WHEN {{ score_expr }} >= 15 THEN 'HIGH'
    WHEN {{ score_expr }} >= 5  THEN 'MEDIUM'
    WHEN {{ score_expr }} >  0  THEN 'LOW'
    ELSE 'NOT_RELEVANT'
END
{% endmacro %}
