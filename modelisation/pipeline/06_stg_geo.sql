-- =============================================================================
-- 06_stg_geo.sql — Staging referentiel geographique (communes, departements, regions)
-- Sources : cartographie-data-engineer.raw.geo_communes / geo_departements / geo_regions
-- Sorties : cartographie-data-engineer.staging.stg_geo__communes
--           cartographie-data-engineer.staging.stg_geo__departements
--           cartographie-data-engineer.staging.stg_geo__regions
-- Depend  : 00_udfs.sql
--
-- Note : executer les 3 blocs CREATE OR REPLACE TABLE de ce script en sequence.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- stg_geo__communes
-- 1 ligne par (NOM, CODE_POSTAL) : une commune peut avoir plusieurs codes postaux
-- codesPostaux serialise en CSV par l'ingestion (format "75001,75002,...")
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_geo__communes`
AS

WITH cleanup AS (
    SELECT
        `cartographie-data-engineer.staging.clean_string`(code)            AS CODE_INSEE,
        `cartographie-data-engineer.staging.clean_string`(nom)             AS NOM,
        `cartographie-data-engineer.staging.clean_string`(codeRegion)      AS CODE_REGION,
        `cartographie-data-engineer.staging.clean_string`(codeDepartement) AS DEPARTEMENT,
        codesPostaux,
        CAST(ROUND(population) AS INT64)                                    AS POPULATION,
        SAFE_CAST(latitude  AS FLOAT64)                                     AS LATITUDE,
        SAFE_CAST(longitude AS FLOAT64)                                     AS LONGITUDE
    FROM `cartographie-data-engineer.raw.geo_communes`
),

exploded AS (
    SELECT
        CODE_INSEE,
        NOM,
        CODE_REGION,
        DEPARTEMENT,
        `cartographie-data-engineer.staging.clean_string`(TRIM(cp)) AS CODE_POSTAL,
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

dedup AS (
    SELECT *
    FROM filtered
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY NOM, CODE_POSTAL
        ORDER BY CODE_INSEE
    ) = 1
)

SELECT * FROM dedup;

-- ---------------------------------------------------------------------------
-- stg_geo__departements
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_geo__departements`
AS

SELECT DISTINCT
    TRIM(CAST(code AS STRING))                                      AS CODE_DEPARTEMENT,
    `cartographie-data-engineer.staging.clean_string`(nom)         AS NOM,
    `cartographie-data-engineer.staging.clean_string`(codeRegion)  AS CODE_REGION
FROM `cartographie-data-engineer.raw.geo_departements`
WHERE code IS NOT NULL;

-- ---------------------------------------------------------------------------
-- stg_geo__regions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_geo__regions`
AS

SELECT DISTINCT
    TRIM(CAST(code AS STRING))                              AS CODE_REGION,
    `cartographie-data-engineer.staging.clean_string`(nom) AS NOM
FROM `cartographie-data-engineer.raw.geo_regions`
WHERE code IS NOT NULL;
