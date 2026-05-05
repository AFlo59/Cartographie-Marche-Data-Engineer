-- =============================================================================
-- 14_mart_fct_offres.sql — Table de faits principale
-- Source  : intermediate.int_france_travail__enrichie
--           intermediate.int_apec__enrichie
--           intermediate.int_jooble__enrichie
-- Sortie  : cartographie-data-engineer.marts.fct_offres
-- Depend  : 08 + 09 + 10 intermediate
--
-- UNION ALL des 3 sources enrichies. Schema unifie lowercase.
-- Cle unique : offre_id_global (prefixe source + offre_id d'origine).
-- Jointures BI recommandees :
--   fct_offres.date_creation -> dim_date.date_id
--   fct_offres.code_postal   -> dim_territoire.code_postal
--   fct_offres.siret_sirene  -> dim_entreprise.siret
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.marts.fct_offres`
AS

WITH france_travail AS (
    SELECT CONCAT('ft_',     offre_id) AS offre_id_global, * FROM `cartographie-data-engineer.intermediate.int_france_travail__enrichie`
),
apec AS (
    SELECT CONCAT('apec_',   offre_id) AS offre_id_global, * FROM `cartographie-data-engineer.intermediate.int_apec__enrichie`
),
jooble AS (
    SELECT CONCAT('jooble_', offre_id) AS offre_id_global, * FROM `cartographie-data-engineer.intermediate.int_jooble__enrichie`
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

SELECT * FROM unified;
