{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        {{ clean_string('code') }}            AS CODE_INSEE,
        {{ clean_string('nom') }}             AS NOM,
        {{ clean_string('codeRegion') }}      AS CODE_REGION,
        {{ clean_string('codeDepartement') }} AS DEPARTEMENT,
        codesPostaux,
        CAST(ROUND(population) AS INT64)      AS POPULATION,
        SAFE_CAST(latitude  AS FLOAT64)       AS LATITUDE,
        SAFE_CAST(longitude AS FLOAT64)       AS LONGITUDE
    FROM {{ source('raw', 'geo_communes') }}
),

-- codesPostaux serialise en CSV par l ingestion (format "75001,75002,...")
exploded AS (
    SELECT
        CODE_INSEE,
        NOM,
        CODE_REGION,
        DEPARTEMENT,
        {{ clean_string('TRIM(cp)') }} AS CODE_POSTAL,
        POPULATION,
        LATITUDE,
        LONGITUDE
    FROM cleanup,
    UNNEST(SPLIT(codesPostaux, ',')) AS cp
),

filtered AS (
    SELECT * FROM exploded
    WHERE CODE_POSTAL IS NOT NULL AND CODE_POSTAL != ''
),

-- Dédoublonnage : garde la première occurrence par (NOM, CODE_POSTAL)
dedup AS (
    SELECT *
    FROM filtered
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY NOM, CODE_POSTAL
        ORDER BY CODE_INSEE
    ) = 1
)

SELECT * FROM dedup
