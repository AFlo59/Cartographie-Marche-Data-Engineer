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

SELECT * FROM unified
