{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        apec_id AS offre_id,

        -- Titre : suppression indicateurs H/F avant normalisation
        {{ clean_string(
            "REGEXP_REPLACE(REGEXP_REPLACE(job_title, r'\\s*\\(\\s*[HF]\\s*/\\s*[FH]\\s*\\)', ''), r'\\s+[HF]/[FH]\\b', '')"
        ) }} AS intitule,

        -- job_description_preview peut contenir du HTML partiel
        {{ clean_html('job_description_preview') }} AS description,

        {{ clean_string('company_name') }} AS nom,

        -- salary_text format APEC : "35/55 k€ annuel sur 13 mois"
        {{ parse_salaire_auto('salary_text') }} AS salaire,

        -- contract_type deja decode par l ingestion (CDI, CDD, Stage...)
        {{ clean_string('contract_type') }} AS code_contrat,

        -- commune et departement deja extraits par l ingestion (_split_location)
        {{ clean_string('commune') }} AS commune,
        UPPER(TRIM(CAST(departement AS STRING))) AS departement,

        {{ clean_string('location_text') }} AS lieu_texte,

        SAFE_CAST(latitude  AS FLOAT64) AS latitude,
        SAFE_CAST(longitude AS FLOAT64) AS longitude,

        published_at  AS date_publication,
        validated_at  AS date_validation,
        scraped_at,

        -- dt = colonne Hive-partition injectée par BigQuery
        COALESCE(
            SAFE_CAST(dt AS DATE),
            SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
            SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
        ) AS date_insertion

    FROM {{ source('raw', 'apec_offres') }}
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
