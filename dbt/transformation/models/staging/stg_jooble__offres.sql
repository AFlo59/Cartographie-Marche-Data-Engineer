{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        -- jooble_id stocké INT64 dans Parquet → CAST STRING pour aligner avec FT/APEC
        CAST(jooble_id AS STRING) AS offre_id,

        -- Titre : suppression indicateurs H/F + bouton "Ajouter aux favoris" injecté par Jooble
        {{ clean_string(
            "REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(title, r'Ajouter aux favoris', ''), r'\\s*\\(\\s*[HF]\\s*/\\s*[FH]\\s*\\)', ''), r'\\s+[HF]/[FH]\\b', '')"
        ) }} AS intitule,

        -- snippet pré-nettoyé par l'ingestion (html.unescape + strip tags), re-normalisation
        {{ clean_html('snippet') }} AS description,

        {{ clean_string('company') }} AS nom,

        -- Texte brut du salaire conservé pour affichage (format Jooble non standard)
        {{ clean_string('salary') }} AS salaire_texte,

        -- type : libellé de contrat brut via API Jooble
        {{ clean_string('type') }} AS code_contrat,

        -- location : format variable "Ville (75)" ou "Ville, Département" ou "75000 Paris"
        CAST(location AS STRING)                                                         AS lieu_raw,
        {{ clean_string('location') }}                                                   AS lieu,

        -- Code postal : extraction du premier groupe de 5 chiffres dans le lieu
        REGEXP_EXTRACT(CAST(location AS STRING), r'(\d{5})')                             AS code_postal,

        -- Ville : suppression du code postal, nettoyage
        {{ clean_string(
            "TRIM(REGEXP_REPLACE(REGEXP_REPLACE(CAST(location AS STRING), r'\\d{5}', ''), r'[,()-]', ' '))"
        ) }}                                                                             AS ville,

        CAST(link AS STRING) AS url,

        -- updated_dt = INT64 epoch-microseconds dans Parquet
        SAFE.TIMESTAMP_MICROS(updated_dt) AS date_publication,

        scraped_at,

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
),

-- Parsing salaire Jooble : format "35 000 € - 45 000 €" ou "35k€ - 45k€" ou "2 500 €/mois"
-- Stratégie : normaliser les espaces dans les nombres (35 000 → 35000), détecter k€ et mensuel
salary_parse AS (
    SELECT
        *,
        -- Flag k€ : "35k" ou "35 K€" → multiplier ×1000
        REGEXP_CONTAINS(UPPER(COALESCE(salaire_texte, '')), r'\d\s*K\b') AS _is_k_format,
        -- Flag mensuel → annualiser ×12
        REGEXP_CONTAINS(UPPER(COALESCE(salaire_texte, '')), r'/MOIS|\bMENSUEL\b|\bPAR MOIS\b') AS _is_monthly,
        -- Texte de travail : suppression des symboles € / EUR pour faciliter la regex
        UPPER(REGEXP_REPLACE(COALESCE(salaire_texte, ''), r'[€EUReur\s]', '')) AS _sal_stripped
    FROM dedup
),

enrich AS (
    SELECT
        offre_id, intitule, description, nom, code_contrat, lieu_raw, lieu,
        code_postal, ville, url, salaire_texte, date_publication, scraped_at, date_insertion,

        -- Salaire min annuel
        SAFE_CAST(
            REGEXP_REPLACE(
                COALESCE(REGEXP_EXTRACT(_sal_stripped, r'^(\d[\d]*(?:[.,]\d+)?)'), ''),
                r',', '.'
            ) AS NUMERIC
        ) * IF(_is_k_format, 1000, 1) * IF(_is_monthly, 12, 1)
        AS salary_min_annual,

        -- Salaire max annuel (après tiret ou slash séparateur)
        SAFE_CAST(
            REGEXP_REPLACE(
                COALESCE(REGEXP_EXTRACT(_sal_stripped, r'[-/](\d[\d]*(?:[.,]\d+)?)'), ''),
                r',', '.'
            ) AS NUMERIC
        ) * IF(_is_k_format, 1000, 1) * IF(_is_monthly, 12, 1)
        AS salary_max_annual,

        -- Type de contrat normalisé
        {{ contract_type_normalized('code_contrat', 'intitule') }} AS contract_type_normalized,

        -- Score de pertinence Data Engineering
        {{ relevance_score_data_eng('intitule', 'description') }}  AS relevance_score

    FROM salary_parse
)

SELECT
    *,
    {{ matching_confidence_data_eng('relevance_score') }} AS matching_confidence
FROM enrich
