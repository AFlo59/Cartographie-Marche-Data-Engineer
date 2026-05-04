{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        id AS offre_id,

        -- Titre : suppression indicateurs H/F avant normalisation
        {{ clean_string(
            "REGEXP_REPLACE(REGEXP_REPLACE(intitule, r'\\s*\\(\\s*[HF]\\s*/\\s*[FH]\\s*\\)', ''), r'\\s+[HF]/[FH]\\b', '')"
        ) }} AS intitule,

        {{ clean_html('description') }}      AS description,
        {{ parse_event_ts('dateCreation') }} AS date_creation,

        -- Code postal : normalisation 4→5 chiffres (quelques offres DOM/TOM)
        CASE
            WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
                THEN CAST(lieuTravail_codePostal AS STRING)
            WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{4}$')
                THEN CONCAT('0', CAST(lieuTravail_codePostal AS STRING))
            ELSE {{ clean_string('CAST(lieuTravail_codePostal AS STRING)') }}
        END AS code_postal,

        -- lieuTravail.commune = code INSEE de la commune (pas le libellé)
        {{ clean_string('CAST(lieuTravail_commune AS STRING)') }} AS code_insee,

        -- Département déduit du code postal ou du libellé (2A/2B + DOM-TOM)
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

        -- lieuTravail.libelle format "75 - Paris" → après clean_string "75 PARIS"
        REGEXP_EXTRACT(
            {{ clean_string('CAST(lieuTravail_libelle AS STRING)') }},
            r'^(?:\d{2,3}|2A|2B)\s+(.+)$'
        ) AS nom_commune,

        {{ clean_string('CAST(entreprise_nom AS STRING)') }}   AS nom,
        {{ clean_siret_valid('entreprise_numeroSiret') }}       AS siret,

        {{ parse_salaire_auto('CAST(salaire_libelle AS STRING)') }} AS salaire,
        {{ clean_string('CAST(salaire_complement1 AS STRING)') }}   AS bonus,

        {{ clean_string('CAST(typeContrat AS STRING)') }}                                  AS code_contrat,
        {{ parse_contrat(clean_string('CAST(typeContratLibelle AS STRING)')) }}            AS contrat,

        {{ clean_string('CAST(codeROME AS STRING)') }}                                     AS code_rome,
        {{ clean_string('CAST(appellationlibelle AS STRING)') }}                           AS appellation,
        {{ clean_string('CAST(experienceExige AS STRING)') }}                              AS experience,
        {{ clean_string('CAST(qualificationCode AS STRING)') }}                            AS qualification,

        -- dt = colonne Hive-partition injectée par BigQuery (STRING "YYYY-MM-DD")
        COALESCE(
            SAFE_CAST(dt AS DATE),
            SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
            SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
        ) AS date_insertion

    FROM {{ source('raw', 'france_travail_offres') }}
),

dedup AS (
    SELECT *
    FROM cleanup
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY offre_id
        ORDER BY date_creation DESC NULLS LAST, date_insertion DESC NULLS LAST
    ) = 1
)

SELECT * FROM dedup
