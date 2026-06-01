{{ config(materialized='table') }}

--
-- Table de faits principale — marché de l'emploi Data Engineering.
-- UNION ALL des 3 sources enrichies (France Travail + APEC + Jooble).
-- Schéma unifié lowercase : les champs non disponibles sur une source sont NULL explicitement.
-- Clé unique : offre_id_global (préfixe source + offre_id d'origine).
--
-- Jointures BI recommandées :
--   fct_offres.date_creation → dim_date.date_id
--   fct_offres.code_postal   → dim_territoire.code_postal
--   fct_offres.siret_sirene  → dim_entreprise.siret
--

WITH france_travail AS (
    SELECT CONCAT('ft_',     offre_id) AS offre_id_global, * FROM {{ ref('int_france_travail__enrichie') }}
),
apec AS (
    SELECT CONCAT('apec_',   offre_id) AS offre_id_global, * FROM {{ ref('int_apec__enrichie') }}
),
jooble AS (
    SELECT CONCAT('jooble_', offre_id) AS offre_id_global, * FROM {{ ref('int_jooble__enrichie') }}
),

unified AS (
    SELECT
        offre_id_global, offre_id, source_offre, url,
        intitule, description, date_creation, date_insertion,
        nom_entreprise_source, nom_entreprise_sirene, nom_entreprise_final,
        siret, siret_sirene, siren_sirene, fiabilite_jointure_sirene,
        code_contrat, contract_type_normalized, type_contrat_libelle, duree_contrat_mois,
        salaire_texte, salary_min_annual, salary_max_annual, bonus,
        code_postal, code_insee, commune, departement, nom_departement,
        code_region, nom_region, latitude, longitude,
        code_naf, code_categorie_juridique, categorie_entreprise, tranche_effectifs,
        code_rome, appellation, experience, qualification,
        relevance_score, matching_confidence
    FROM france_travail

    UNION ALL

    SELECT
        offre_id_global, offre_id, source_offre, url,
        intitule, description, date_creation, date_insertion,
        nom_entreprise_source, nom_entreprise_sirene, nom_entreprise_final,
        siret, siret_sirene, siren_sirene, fiabilite_jointure_sirene,
        code_contrat, contract_type_normalized, type_contrat_libelle, duree_contrat_mois,
        salaire_texte, salary_min_annual, salary_max_annual, bonus,
        code_postal, code_insee, commune, departement, nom_departement,
        code_region, nom_region, latitude, longitude,
        code_naf, code_categorie_juridique, categorie_entreprise, tranche_effectifs,
        code_rome, appellation, experience, qualification,
        relevance_score, matching_confidence
    FROM apec

    UNION ALL

    SELECT
        offre_id_global, offre_id, source_offre, url,
        intitule, description, date_creation, date_insertion,
        nom_entreprise_source, nom_entreprise_sirene, nom_entreprise_final,
        siret, siret_sirene, siren_sirene, fiabilite_jointure_sirene,
        code_contrat, contract_type_normalized, type_contrat_libelle, duree_contrat_mois,
        salaire_texte, salary_min_annual, salary_max_annual, bonus,
        code_postal, code_insee, commune, departement, nom_departement,
        code_region, nom_region, latitude, longitude,
        code_naf, code_categorie_juridique, categorie_entreprise, tranche_effectifs,
        code_rome, appellation, experience, qualification,
        relevance_score, matching_confidence
    FROM jooble
)

final AS (
    SELECT
        u.*,

        -- Source (dim_source_offre)
        src.nom_affiche                                                 AS source_nom_affiche,
        src.type_source                                                 AS source_type,
        src.perimetre_public                                            AS source_perimetre,
        src.est_source_officielle,

        -- Entreprise
        u.nom_entreprise_final                                          AS entreprise,
        u.categorie_entreprise                                          AS taille_entreprise,
        ent.libelle_tranche_effectifs                                   AS effectifs_libelle,

        -- Contrat (alias lisible)
        u.contract_type_normalized                                      AS type_contrat,

        -- Salaire médian estimé (logique identique à mart_marche_emploi)
        CASE
            WHEN u.salary_min_annual IS NOT NULL AND u.salary_max_annual IS NOT NULL
                THEN ROUND((u.salary_min_annual + u.salary_max_annual) / 2, 0)
            WHEN u.salary_min_annual IS NOT NULL
                THEN u.salary_min_annual
        END                                                             AS salary_median_estimate,

        -- Semaine de publication (logique identique à mart_marche_emploi)
        DATE_TRUNC(u.date_creation, WEEK(MONDAY))                      AS semaine_publication

    FROM unified u
    LEFT JOIN {{ ref('dim_source_offre') }} src ON u.source_offre = src.source_id
    LEFT JOIN {{ ref('dim_entreprise') }}   ent ON u.siret_sirene  = ent.siret
)

SELECT * FROM final
