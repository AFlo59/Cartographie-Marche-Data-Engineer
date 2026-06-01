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
        *,

        -- Source enrichie (affichage BI)
        CASE source_offre
            WHEN 'france_travail' THEN 'France Travail'
            WHEN 'apec'           THEN 'APEC'
            WHEN 'jooble'         THEN 'Jooble'
        END                                                             AS source_nom_affiche,
        CASE source_offre
            WHEN 'france_travail' THEN 'Pôle emploi officiel'
            WHEN 'apec'           THEN 'Cadres / Ingénieurs'
            WHEN 'jooble'         THEN 'Agrégateur'
        END                                                             AS source_type,
        'National'                                                      AS source_perimetre,
        source_offre IN ('france_travail', 'apec')                     AS est_source_officielle,

        -- Entreprise (alias lisibles BI)
        nom_entreprise_final                                            AS entreprise,
        categorie_entreprise                                            AS taille_entreprise,
        CASE tranche_effectifs
            WHEN 'NN' THEN 'Non renseigné'
            WHEN '00' THEN '0 salarié'
            WHEN '01' THEN '1 ou 2 salariés'
            WHEN '02' THEN '3 à 5 salariés'
            WHEN '03' THEN '6 à 9 salariés'
            WHEN '11' THEN '10 à 19 salariés'
            WHEN '12' THEN '20 à 49 salariés'
            WHEN '21' THEN '50 à 99 salariés'
            WHEN '22' THEN '100 à 199 salariés'
            WHEN '31' THEN '200 à 249 salariés'
            WHEN '32' THEN '250 à 499 salariés'
            WHEN '41' THEN '500 à 999 salariés'
            WHEN '42' THEN '1 000 à 1 999 salariés'
            WHEN '51' THEN '2 000 à 4 999 salariés'
            WHEN '52' THEN '5 000 à 9 999 salariés'
            WHEN '53' THEN '10 000 salariés et plus'
        END                                                             AS effectifs_libelle,

        -- Contrat (alias lisible)
        contract_type_normalized                                        AS type_contrat,

        -- Salaire médian estimé
        SAFE_DIVIDE(salary_min_annual + salary_max_annual, 2)          AS salary_median_estimate,

        -- Semaine de publication (lundi → dimanche)
        DATE_TRUNC(date_creation, WEEK(MONDAY))                        AS semaine_publication

    FROM unified
)

SELECT * FROM final
