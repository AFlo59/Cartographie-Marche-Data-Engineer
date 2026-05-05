{{ config(materialized='view') }}

--
-- Vue BI principale — marché de l'emploi Data Engineering toutes sources.
-- Passthrough depuis fct_offres avec colonnes métier enrichies pour self-service BI.
-- Compatible : Looker Studio, Power BI, Metabase, Tableau, Superset.
--

SELECT
    -- Identifiants
    offre_id_global,
    source_offre,

    -- Contenu
    intitule,
    date_creation,
    date_insertion,
    url,

    -- Entreprise
    nom_entreprise_final                                AS entreprise,
    fiabilite_jointure_sirene,
    categorie_entreprise                                AS taille_entreprise,
    CASE tranche_effectifs
        WHEN '00' THEN '0 salarié'
        WHEN '01' THEN '1 à 2'
        WHEN '02' THEN '3 à 5'
        WHEN '03' THEN '6 à 9'
        WHEN '11' THEN '10 à 19'
        WHEN '12' THEN '20 à 49'
        WHEN '21' THEN '50 à 99'
        WHEN '22' THEN '100 à 199'
        WHEN '31' THEN '200 à 249'
        WHEN '32' THEN '250 à 499'
        WHEN '41' THEN '500 à 999'
        WHEN '42' THEN '1 000 à 1 999'
        WHEN '51' THEN '2 000 à 4 999'
        WHEN '52' THEN '5 000 à 9 999'
        WHEN '53' THEN '10 000 +'
        ELSE NULL
    END                                                 AS effectifs_libelle,
    code_naf,

    -- Contrat
    contract_type_normalized                            AS type_contrat,
    duree_contrat_mois,

    -- Salaire
    salary_min_annual,
    salary_max_annual,
    CASE
        WHEN salary_min_annual IS NOT NULL AND salary_max_annual IS NOT NULL
            THEN ROUND((salary_min_annual + salary_max_annual) / 2, 0)
        WHEN salary_min_annual IS NOT NULL
            THEN salary_min_annual
        ELSE NULL
    END                                                 AS salary_median_estimate,
    salaire_texte,

    -- Localisation
    commune,
    departement,
    nom_departement,
    code_region,
    nom_region,
    latitude,
    longitude,

    -- Classification métier (France Travail uniquement)
    code_rome,
    appellation,
    experience,

    -- Pertinence Data Engineering
    relevance_score,
    matching_confidence,

    -- Agrégat semaine de publication (graphiques de tendances)
    DATE_TRUNC(date_creation, WEEK(MONDAY))             AS semaine_publication

FROM {{ ref('fct_offres') }}
