-- =============================================================================
-- 01_stg_france_travail.sql — Staging offres France Travail
-- Source  : cartographie-data-engineer.raw.france_travail_offres (External Table Hive)
-- Sortie  : cartographie-data-engineer.staging.stg_france_travail__offres
-- Depend  : 00_udfs.sql
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_france_travail__offres`
AS

WITH cleanup AS (
    SELECT
        id AS offre_id,

        -- Titre : suppression indicateur H/F avant normalisation
        `cartographie-data-engineer.staging.clean_string`(
            REGEXP_REPLACE(
                REGEXP_REPLACE(intitule, r'\s*\(\s*[HF]\s*/\s*[FH]\s*\)', ''),
                r'\s+[HF]/[FH]\b', ''
            )
        ) AS intitule,

        `cartographie-data-engineer.staging.clean_html`(description) AS description,

        `cartographie-data-engineer.staging.parse_event_ts`(CAST(dateCreation AS STRING)) AS date_creation,

        -- Code postal : normalisation 4->5 chiffres (DOM-TOM)
        CASE
            WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
                THEN CAST(lieuTravail_codePostal AS STRING)
            WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{4}$')
                THEN CONCAT('0', CAST(lieuTravail_codePostal AS STRING))
            ELSE `cartographie-data-engineer.staging.clean_string`(CAST(lieuTravail_codePostal AS STRING))
        END AS code_postal,

        -- lieuTravail.commune = code INSEE (pas le libelle)
        `cartographie-data-engineer.staging.clean_string`(CAST(lieuTravail_commune AS STRING)) AS code_insee,

        -- Departement deduit du code postal ou libelle (2A/2B + DOM-TOM)
        CASE
            WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^(97[1-6]|98[0-9])\d{2}$')
                THEN SUBSTR(CAST(lieuTravail_codePostal AS STRING), 1, 3)
            WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
                THEN SUBSTR(CAST(lieuTravail_codePostal AS STRING), 1, 2)
            WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^(2A|2B)\b')
                THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(2A|2B)\b')
            WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^(97[1-6]|98[0-9])\b')
                THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(97[1-6]|98[0-9])\b')
            WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^\d{2}\b')
                THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(\d{2})\b')
            ELSE NULL
        END AS departement,

        -- lieuTravail.libelle "75 - Paris" -> apres clean_string "75 PARIS" -> extrait "PARIS"
        REGEXP_EXTRACT(
            `cartographie-data-engineer.staging.clean_string`(CAST(lieuTravail_libelle AS STRING)),
            r'^(?:\d{2,3}|2A|2B)\s+(.+)$'
        ) AS nom_commune,

        `cartographie-data-engineer.staging.clean_string`(CAST(entreprise_nom AS STRING))  AS nom,
        `cartographie-data-engineer.staging.clean_siret_valid`(entreprise_numeroSiret)     AS siret,

        CAST(salaire_libelle AS STRING)                                                     AS salaire_texte_raw,
        `cartographie-data-engineer.staging.parse_salaire_auto`(CAST(salaire_libelle AS STRING)) AS salaire,
        `cartographie-data-engineer.staging.clean_string`(CAST(salaire_complement1 AS STRING))   AS bonus,

        `cartographie-data-engineer.staging.clean_string`(CAST(typeContrat AS STRING))          AS code_contrat,
        `cartographie-data-engineer.staging.parse_contrat`(
            `cartographie-data-engineer.staging.clean_string`(CAST(typeContratLibelle AS STRING))
        )                                                                                        AS contrat,

        `cartographie-data-engineer.staging.clean_string`(CAST(codeROME AS STRING))             AS code_rome,
        `cartographie-data-engineer.staging.clean_string`(CAST(appellationlibelle AS STRING))   AS appellation,
        `cartographie-data-engineer.staging.clean_string`(CAST(experienceExige AS STRING))      AS experience,
        `cartographie-data-engineer.staging.clean_string`(CAST(qualificationCode AS STRING))    AS qualification,

        COALESCE(
            SAFE_CAST(dt AS DATE),
            SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
            SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
        ) AS date_insertion

    FROM `cartographie-data-engineer.raw.france_travail_offres`
),

dedup AS (
    SELECT *
    FROM cleanup
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY offre_id
        ORDER BY date_creation DESC NULLS LAST, date_insertion DESC NULLS LAST
    ) = 1
),

enrich AS (
    SELECT
        *,
        salaire.min_annuel AS salary_min_annual,
        salaire.max_annuel AS salary_max_annual,
        `cartographie-data-engineer.staging.contract_type_normalized`(
            code_contrat, contrat.type_contrat
        ) AS contract_type_normalized,
        `cartographie-data-engineer.staging.relevance_score_data_eng`(intitule, description) AS relevance_score
    FROM dedup
)

SELECT
    *,
    `cartographie-data-engineer.staging.matching_confidence_data_eng`(relevance_score) AS matching_confidence
FROM enrich;
