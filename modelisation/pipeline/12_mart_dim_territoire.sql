-- =============================================================================
-- 12_mart_dim_territoire.sql — Dimension territoire
-- Source  : staging.stg_geo__communes + stg_geo__departements + stg_geo__regions
-- Sortie  : cartographie-data-engineer.marts.dim_territoire
-- Depend  : 06_stg_geo.sql
--
-- 1 ligne par (commune x code_postal) — une commune peut avoir plusieurs codes postaux.
-- Jointure depuis fct_offres sur code_postal ou code_departement.
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.marts.dim_territoire`
AS

SELECT
    c.CODE_POSTAL                       AS code_postal,
    c.CODE_INSEE                        AS code_insee,
    c.DEPARTEMENT                       AS code_departement,
    c.CODE_REGION                       AS code_region,
    c.NOM                               AS nom_commune,
    d.NOM                               AS nom_departement,
    r.NOM                               AS nom_region,
    c.POPULATION                        AS population,
    c.LATITUDE                          AS latitude,
    c.LONGITUDE                         AS longitude

FROM `cartographie-data-engineer.staging.stg_geo__communes` c
LEFT JOIN `cartographie-data-engineer.staging.stg_geo__departements` d
    ON c.DEPARTEMENT = d.CODE_DEPARTEMENT
LEFT JOIN `cartographie-data-engineer.staging.stg_geo__regions` r
    ON c.CODE_REGION = r.CODE_REGION;
