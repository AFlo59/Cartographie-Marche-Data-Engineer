{{
  config(materialized='table')
}}

WITH

null_nom AS (
  SELECT id, description, departement, nom_commune
  FROM {{ ref('staging_offres') }}
  WHERE nom IS NULL OR nom = ''
),

etab_noms AS (
  SELECT DISTINCT NOM, DEPARTEMENT, NOM_COMMUNE
  FROM {{ ref('staging.etablissements') }}
  WHERE NOM IS NOT NULL AND NOM != ''
    AND DEPARTEMENT IS NOT NULL
    AND NOM_COMMUNE IS NOT NULL
),

matched AS (
  SELECT
    o.id,
    e.NOM AS nom_extrait
  FROM null_nom o
  JOIN etab_noms e
    ON  o.departement = e.DEPARTEMENT
    AND o.nom_commune = e.NOM_COMMUNE
    AND STRPOS(o.description, e.NOM) > 0
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY o.id
    ORDER BY LENGTH(e.NOM) DESC
  ) = 1
)

SELECT
  o.* REPLACE(COALESCE(m.nom_extrait, o.nom) AS NOM)
FROM {{ ref('staging_offres') }} o
LEFT JOIN matched m ON o.id = m.id
