{{ config(
    materialized='incremental',
    unique_key='offre_id',
    incremental_strategy='merge'
) }}

WITH offres AS (
    SELECT * FROM {{ ref('stg_france_travail__offres') }}
    {% if is_incremental() %}
    -- Fenetre -7j pour absorber les partitions tardives
    WHERE date_insertion >= (
        SELECT COALESCE(MAX(date_insertion) - INTERVAL 7 DAY, DATE('2020-01-01'))
        FROM {{ this }}
    )
    {% endif %}
),

-- Une seule ligne par SIRET : premiere combinaison NOM + NOM_COMMUNE rencontree
sirene_dedup AS (
    SELECT
        SIRET,
        NOM                     AS nom_entreprise_sirene,
        SUBSTR(SIRET, 1, 9)     AS SIREN,
        CODE_NAF,
        DEPARTEMENT             AS departement_sirene,
        LATITUDE                AS latitude_sirene,
        LONGITUDE               AS longitude_sirene
    FROM {{ ref('stg_sirene__etablissements') }}
    WHERE SIRET IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY SIRET ORDER BY NOM NULLS LAST) = 1
),

-- Une seule ligne par code postal : priorite au code INSEE le plus petit
geo AS (
    SELECT
        CODE_POSTAL,
        CODE_INSEE,
        NOM         AS commune,
        CODE_REGION
    FROM {{ ref('stg_geo__communes') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CODE_POSTAL ORDER BY CODE_INSEE) = 1
)

SELECT
    o.offre_id,
    o.intitule,
    o.code_contrat,
    o.contrat.type_contrat      AS type_contrat,
    o.contrat.duree_mois        AS duree_contrat_mois,
    o.date_creation,
    o.departement,
    COALESCE(g.commune, o.nom_commune) AS commune,
    g.CODE_REGION               AS code_region,
    o.siret,
    s.SIREN                     AS siren,
    s.CODE_NAF                  AS code_naf,
    o.salaire,
    o.code_rome,
    o.appellation,
    o.experience,
    o.date_insertion
FROM offres o
LEFT JOIN sirene_dedup s ON o.siret = s.SIRET
LEFT JOIN geo g          ON o.code_postal = g.CODE_POSTAL
