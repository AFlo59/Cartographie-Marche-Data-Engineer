{{ config(materialized='view') }}

--
-- Vue BI principale — marché de l'emploi Data Engineering toutes sources.
-- Passthrough depuis fct_offres avec colonnes métier enrichies pour self-service BI.
-- Jointure dim_source_offre pour exposer les métadonnées de chaque plateforme.
-- Compatible : Looker Studio, Power BI, Metabase, Tableau, Superset.
--

SELECT
    -- Identifiants
    f.offre_id_global,
    f.source_offre,

    -- Source (dim_source_offre)
    s.nom_affiche                                       AS source_nom_affiche,
    s.type_source                                       AS source_type,
    s.perimetre_public                                  AS source_perimetre,
    s.est_source_officielle,

    -- Contenu
    f.intitule,
    f.date_creation,
    f.date_insertion,
    f.url,

    -- Entreprise
    f.nom_entreprise_final                              AS entreprise,
    f.fiabilite_jointure_sirene,
    f.categorie_entreprise                              AS taille_entreprise,
    CASE f.tranche_effectifs
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
    f.code_naf,

    -- Contrat
    f.contract_type_normalized                          AS type_contrat,
    f.duree_contrat_mois,

    -- Salaire
    f.salary_min_annual,
    f.salary_max_annual,
    CASE
        WHEN f.salary_min_annual IS NOT NULL AND f.salary_max_annual IS NOT NULL
            THEN ROUND((f.salary_min_annual + f.salary_max_annual) / 2, 0)
        WHEN f.salary_min_annual IS NOT NULL
            THEN f.salary_min_annual
        ELSE NULL
    END                                                 AS salary_median_estimate,
    f.salaire_texte,

    -- Localisation
    f.commune,
    f.departement,
    f.nom_departement,
    f.code_region,
    f.nom_region,
    f.latitude,
    f.longitude,

    -- Classification métier (France Travail uniquement)
    f.code_rome,
    f.appellation,
    f.experience,

    -- Pertinence Data Engineering
    f.relevance_score,
    f.matching_confidence,

    -- Agrégat semaine de publication (graphiques de tendances)
    DATE_TRUNC(f.date_creation, WEEK(MONDAY))           AS semaine_publication

FROM {{ ref('fct_offres') }} f
LEFT JOIN {{ ref('dim_source_offre') }} s ON f.source_offre = s.source_id
