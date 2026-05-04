{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        jooble_id AS offre_id,

        -- Titre : suppression indicateurs H/F avant normalisation
        {{ clean_string(
            "REGEXP_REPLACE(REGEXP_REPLACE(title, r'\\s*\\(\\s*[HF]\\s*/\\s*[FH]\\s*\\)', ''), r'\\s+[HF]/[FH]\\b', '')"
        ) }} AS intitule,

        -- snippet pre-nettoye par l ingestion (html.unescape + strip tags), on re-normalise
        {{ clean_html('snippet') }} AS description,

        {{ clean_string('company') }} AS nom,

        -- salary : format Jooble ("35 000 € - 45 000 €") non compatible PARSE_SALAIRE_AUTO
        -- → conservation comme texte normalisé
        {{ clean_string('salary') }} AS salaire_texte,

        -- type : libelle de contrat brut via API Jooble
        {{ clean_string('type') }} AS code_contrat,

        {{ clean_string('location') }} AS lieu,

        -- link : URL directe vers l offre (conservee brute)
        CAST(link AS STRING) AS url,

        -- updated_dt = INT64 epoch-microseconds dans Parquet, BigQuery ne cast pas directement
        SAFE.TIMESTAMP_MICROS(updated_dt) AS date_publication,

        scraped_at,

        -- dt = colonne Hive-partition injectée par BigQuery
        COALESCE(
            SAFE_CAST(dt AS DATE),
            SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
            SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
        ) AS date_insertion

    FROM {{ source('raw', 'jooble_offres') }}
    WHERE jooble_id IS NOT NULL
),

dedup AS (
    SELECT *
    FROM cleanup
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY offre_id
        ORDER BY date_publication DESC NULLS LAST, date_insertion DESC NULLS LAST
    ) = 1
)

SELECT * FROM dedup
