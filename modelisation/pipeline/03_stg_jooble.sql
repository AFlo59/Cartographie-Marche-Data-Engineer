-- =============================================================================
-- 03_stg_jooble.sql — Staging offres Jooble
-- Source  : cartographie-data-engineer.raw.jooble_offres (External Table Hive)
-- Sortie  : cartographie-data-engineer.staging.stg_jooble__offres
-- Depend  : 00_udfs.sql
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_jooble__offres`
AS

WITH cleanup AS (
    SELECT
        -- jooble_id stocke INT64 dans Parquet → CAST STRING pour aligner avec FT/APEC
        CAST(jooble_id AS STRING) AS offre_id,

        -- Titre : suppression bouton "Ajouter aux favoris" injecte par Jooble + H/F
        `cartographie-data-engineer.staging.clean_string`(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(title, r'Ajouter aux favoris', ''),
                    r'\s*\(\s*[HF]\s*/\s*[FH]\s*\)', ''
                ),
                r'\s+[HF]/[FH]\b', ''
            )
        ) AS intitule,

        -- snippet pre-nettoye par l'ingestion, re-normalisation
        `cartographie-data-engineer.staging.clean_html`(snippet) AS description,

        `cartographie-data-engineer.staging.clean_string`(company) AS nom,

        -- Texte brut salaire conserve pour affichage (format Jooble non standard)
        `cartographie-data-engineer.staging.clean_string`(salary) AS salaire_texte,

        -- type : libelle de contrat brut via API Jooble
        `cartographie-data-engineer.staging.clean_string`(type) AS code_contrat,

        -- location : format variable "Ville (75)" ou "75000 Paris"
        CAST(location AS STRING) AS lieu_raw,
        `cartographie-data-engineer.staging.clean_string`(location) AS lieu,

        -- Code postal : premier groupe de 5 chiffres dans le lieu
        REGEXP_EXTRACT(CAST(location AS STRING), r'(\d{5})') AS code_postal,

        -- Ville : suppression code postal, nettoyage
        `cartographie-data-engineer.staging.clean_string`(
            TRIM(REGEXP_REPLACE(
                REGEXP_REPLACE(CAST(location AS STRING), r'\d{5}', ''),
                r'[,()-]', ' '
            ))
        ) AS ville,

        CAST(link AS STRING) AS url,

        -- updated_dt = INT64 epoch-microseconds dans Parquet
        SAFE.TIMESTAMP_MICROS(updated_dt) AS date_publication,
        scraped_at,

        COALESCE(
            SAFE_CAST(dt AS DATE),
            SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
            SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
        ) AS date_insertion

    FROM `cartographie-data-engineer.raw.jooble_offres`
    WHERE jooble_id IS NOT NULL
),

dedup AS (
    SELECT *
    FROM cleanup
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY offre_id
        ORDER BY date_publication DESC NULLS LAST, date_insertion DESC NULLS LAST
    ) = 1
),

-- Parsing salaire Jooble : "35 000 EUR - 45 000 EUR" ou "35k EUR" ou "2 500 EUR/mois"
salary_parse AS (
    SELECT
        *,
        REGEXP_CONTAINS(UPPER(COALESCE(salaire_texte, '')), r'\d\s*K\b')               AS _is_k_format,
        REGEXP_CONTAINS(UPPER(COALESCE(salaire_texte, '')), r'/MOIS|\bMENSUEL\b|\bPAR MOIS\b') AS _is_monthly,
        UPPER(REGEXP_REPLACE(COALESCE(salaire_texte, ''), r'[€EUReur\s]', ''))          AS _sal_stripped
    FROM dedup
),

enrich AS (
    SELECT
        offre_id, intitule, description, nom, code_contrat,
        lieu_raw, lieu, code_postal, ville, url, salaire_texte,
        date_publication, scraped_at, date_insertion,

        -- Salaire min annuel
        SAFE_CAST(
            REGEXP_REPLACE(
                COALESCE(REGEXP_EXTRACT(_sal_stripped, r'^(\d[\d]*(?:[.,]\d+)?)'), ''),
                r',', '.'
            ) AS NUMERIC
        ) * IF(_is_k_format, 1000, 1) * IF(_is_monthly, 12, 1) AS salary_min_annual,

        -- Salaire max annuel (apres tiret ou slash separateur)
        SAFE_CAST(
            REGEXP_REPLACE(
                COALESCE(REGEXP_EXTRACT(_sal_stripped, r'[-/](\d[\d]*(?:[.,]\d+)?)'), ''),
                r',', '.'
            ) AS NUMERIC
        ) * IF(_is_k_format, 1000, 1) * IF(_is_monthly, 12, 1) AS salary_max_annual,

        `cartographie-data-engineer.staging.contract_type_normalized`(code_contrat, intitule) AS contract_type_normalized,
        `cartographie-data-engineer.staging.relevance_score_data_eng`(intitule, description)  AS relevance_score

    FROM salary_parse
)

SELECT
    *,
    `cartographie-data-engineer.staging.matching_confidence_data_eng`(relevance_score) AS matching_confidence
FROM enrich;
