{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        {{ CLEAN_STRING('code') }} AS CODE_INSEE,
        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    {{ CLEAN_STRING('nom') }},
                    r'\s*\(?\b[HF]/[FH]\b\)?',
                    ''
                ),
                r'\s*[/\\]\s*\S+',
                ''
            )
        ) AS NOM,
        {{ CLEAN_STRING('codeRegion') }}      AS REGION_FK,
        {{ CLEAN_STRING('codeDepartement') }} AS DEPARTEMENT,
        codesPostaux,
        CAST(ROUND(population) AS INT64)  AS POPULATION,
        SAFE_CAST(latitude  AS FLOAT64)   AS LATITUDE,
        SAFE_CAST(longitude AS FLOAT64)   AS LONGITUDE

    FROM {{ source('raw', 'geo_communes') }}
),

-- SPLIT DES CODES POSTAUX
exploded AS (
    SELECT
        CODE_INSEE,
        NOM,
        REGION_FK,
        DEPARTEMENT,
        {{ CLEAN_STRING('TRIM(cp)') }} AS CODE_POSTAL,
        POPULATION,
        LATITUDE,
        LONGITUDE
    FROM cleanup,
    UNNEST(SPLIT(codesPostaux, ',')) AS cp
),

-- VALIDATION + FILTRE
filtered AS (
    SELECT *
    FROM exploded
    WHERE CODE_POSTAL IS NOT NULL
        AND CODE_POSTAL != ''
),

-- DEDUP LOGIQUE METIER
dedup AS (
    SELECT *
    FROM filtered
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY NOM, CODE_POSTAL
        ORDER BY CODE_INSEE
    ) = 1
)

SELECT * FROM dedup
