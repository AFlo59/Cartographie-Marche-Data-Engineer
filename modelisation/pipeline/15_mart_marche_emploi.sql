-- =============================================================================
-- 15_mart_marche_emploi.sql — Vue BI principale
-- Source  : marts.fct_offres
-- Sortie  : cartographie-data-engineer.marts.mart_marche_emploi (VIEW)
-- Depend  : 14_mart_fct_offres.sql
--
-- Passthrough depuis fct_offres avec colonnes metier enrichies pour self-service BI.
-- Compatible Looker Studio, Power BI, Metabase, Tableau, Superset.
-- Colonnes ajoutees :
--   effectifs_libelle    : libelle lisible de la tranche effectifs
--   salary_median_estimate : estimation salaire median = (min + max) / 2
--   semaine_publication  : debut de semaine (lundi) de la date de publication
-- =============================================================================

CREATE OR REPLACE VIEW `cartographie-data-engineer.marts.mart_marche_emploi`
AS

SELECT
    offre_id_global,
    source_offre,
    intitule,
    date_creation,
    date_insertion,
    url,

    -- Entreprise
    nom_entreprise_final                                AS entreprise,
    fiabilite_jointure_sirene,
    categorie_entreprise                                AS taille_entreprise,
    CASE tranche_effectifs
        WHEN '00' THEN '0 salarie'
        WHEN '01' THEN '1 a 2'
        WHEN '02' THEN '3 a 5'
        WHEN '03' THEN '6 a 9'
        WHEN '11' THEN '10 a 19'
        WHEN '12' THEN '20 a 49'
        WHEN '21' THEN '50 a 99'
        WHEN '22' THEN '100 a 199'
        WHEN '31' THEN '200 a 249'
        WHEN '32' THEN '250 a 499'
        WHEN '41' THEN '500 a 999'
        WHEN '42' THEN '1 000 a 1 999'
        WHEN '51' THEN '2 000 a 4 999'
        WHEN '52' THEN '5 000 a 9 999'
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

    -- Classification metier (France Travail uniquement)
    code_rome,
    appellation,
    experience,

    -- Pertinence Data Engineering
    relevance_score,
    matching_confidence,

    -- Agregat semaine de publication (graphiques de tendances)
    DATE_TRUNC(date_creation, WEEK(MONDAY))             AS semaine_publication

FROM `cartographie-data-engineer.marts.fct_offres`;
