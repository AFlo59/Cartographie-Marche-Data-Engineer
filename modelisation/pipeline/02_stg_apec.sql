-- =============================================================================
-- 02_stg_apec.sql — Staging offres APEC
-- Source  : cartographie-data-engineer.raw.apec_offres (External Table Hive)
-- Sortie  : cartographie-data-engineer.staging.stg_apec__offres
-- Depend  : 00_udfs.sql
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_apec__offres`
AS

WITH cleanup AS (
    SELECT
        apec_id AS offre_id,

        -- Titre : suppression indicateur H/F
        `cartographie-data-engineer.staging.clean_string`(
            REGEXP_REPLACE(
                REGEXP_REPLACE(job_title, r'\s*\(\s*[HF]\s*/\s*[FH]\s*\)', ''),
                r'\s+[HF]/[FH]\b', ''
            )
        ) AS intitule,

        -- job_description_preview peut contenir du HTML partiel
        `cartographie-data-engineer.staging.clean_html`(job_description_preview) AS description,

        `cartographie-data-engineer.staging.clean_string`(company_name) AS nom,

        -- Format APEC : "35/55 k€ annuel sur 13 mois"
        CAST(salary_text AS STRING)                                          AS salaire_texte_raw,
        `cartographie-data-engineer.staging.parse_salaire_auto`(salary_text) AS salaire,

        -- contract_type deja decode par l'ingestion (CDI, CDD, Stage...)
        `cartographie-data-engineer.staging.clean_string`(contract_type) AS code_contrat,

        -- commune et departement extraits par l'ingestion (_split_location)
        `cartographie-data-engineer.staging.clean_string`(commune)    AS commune,
        UPPER(TRIM(CAST(departement AS STRING)))                        AS departement,

        `cartographie-data-engineer.staging.clean_string`(location_text) AS lieu_texte,

        SAFE_CAST(latitude  AS FLOAT64) AS latitude,
        SAFE_CAST(longitude AS FLOAT64) AS longitude,

        published_at AS date_publication,
        validated_at AS date_validation,
        scraped_at,

        COALESCE(
            SAFE_CAST(dt AS DATE),
            SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
            SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
        ) AS date_insertion

    FROM `cartographie-data-engineer.raw.apec_offres`
),

dedup AS (
    SELECT *
    FROM cleanup
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY offre_id
        ORDER BY date_publication DESC NULLS LAST, date_insertion DESC NULLS LAST
    ) = 1
),

enrich AS (
    SELECT
        *,
        salaire.min_annuel AS salary_min_annual,
        salaire.max_annuel AS salary_max_annual,
        `cartographie-data-engineer.staging.contract_type_normalized`(
            code_contrat, intitule
        ) AS contract_type_normalized,
        `cartographie-data-engineer.staging.relevance_score_data_eng`(intitule, description) AS relevance_score
    FROM dedup
)

SELECT
    *,
    `cartographie-data-engineer.staging.matching_confidence_data_eng`(relevance_score) AS matching_confidence
FROM enrich;
