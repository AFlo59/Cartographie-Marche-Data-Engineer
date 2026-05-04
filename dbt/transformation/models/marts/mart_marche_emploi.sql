{{ config(materialized='view') }}

SELECT
    offre_id,
    intitule,
    code_contrat,
    type_contrat,
    duree_contrat_mois,
    date_creation,
    departement,
    commune,
    code_region,
    siret,
    siren,
    code_naf,
    salaire,
    code_rome,
    appellation,
    experience,
    date_insertion
FROM {{ ref('int_offres_enrichies') }}
