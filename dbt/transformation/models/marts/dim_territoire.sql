{{ config(materialized='table') }}

--
-- Dimension territoire — référentiel géographique complet France métropolitaine + DOM-TOM.
-- 1 ligne par (commune × code postal) : plusieurs codes postaux par commune → plusieurs lignes.
-- Clé naturelle : (code_postal, code_insee).
-- Jointure depuis fct_offres sur code_postal ou code_departement.
--

SELECT
    -- Clés géographiques
    c.CODE_POSTAL,
    c.CODE_INSEE,
    c.DEPARTEMENT                   AS code_departement,
    c.CODE_REGION                   AS code_region,

    -- Libellés
    c.NOM                           AS nom_commune,
    d.NOM                           AS nom_departement,
    r.NOM                           AS nom_region,

    -- Données démographiques et géospatiales
    c.POPULATION,
    c.LATITUDE,
    c.LONGITUDE

FROM {{ ref('stg_geo__communes') }} c
LEFT JOIN {{ ref('stg_geo__departements') }} d ON c.DEPARTEMENT = d.CODE_DEPARTEMENT
LEFT JOIN {{ ref('stg_geo__regions') }}     r ON c.CODE_REGION  = r.CODE_REGION
