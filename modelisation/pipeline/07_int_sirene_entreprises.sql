-- =============================================================================
-- 07_int_sirene_entreprises.sql — Table de reference SIRENE consolidee
-- Source  : staging.stg_sirene__etablissements + staging.stg_sirene__unites_legales
-- Sortie  : cartographie-data-engineer.intermediate.int_sirene__entreprises
-- Depend  : 04_stg_sirene_etablissements.sql + 05_stg_sirene_unites_legales.sql + 00_udfs.sql
--
-- 1 ligne par SIRET actif. Joint etablissement (coordonnees, NAF local) avec
-- unite legale (raison sociale, categorie juridique, taille) sur SIREN commun.
-- Precalcule nom_normalise pour jointure rapide sur nom d'entreprise dans les offres.
-- Colonnes toutes en lowercase_snake_case (normalisation couche intermediate).
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.intermediate.int_sirene__entreprises`
AS

WITH etab AS (
    SELECT
        SIRET                  AS siret,
        SUBSTR(SIRET, 1, 9)    AS siren,
        NOM                    AS nom,
        NOM_COMMUNE            AS nom_commune,
        CODE_INSEE             AS code_insee,
        CODE_POSTAL            AS code_postal,
        DEPARTEMENT            AS departement,
        CODE_NAF               AS code_naf_etab,
        LATITUDE               AS latitude,
        LONGITUDE              AS longitude
    FROM `cartographie-data-engineer.staging.stg_sirene__etablissements`
    WHERE SIRET IS NOT NULL
),

ul AS (
    SELECT
        SIREN                                       AS siren,
        NOM_COMPLET                                 AS nom_unite_legale,
        CODE_NAF                                    AS code_naf_ul,
        CODE_CATEGORIE_JURIDIQUE                    AS code_categorie_juridique,
        CATEGORIE_ENTREPRISE                        AS categorie_entreprise,
        TRANCHE_EFFECTIFS                           AS tranche_effectifs
    FROM `cartographie-data-engineer.staging.stg_sirene__unites_legales`
),

joined AS (
    SELECT
        e.siret,
        e.siren,
        COALESCE(e.nom, ul.nom_unite_legale)        AS nom,
        ul.nom_unite_legale,
        e.nom_commune,
        e.code_insee,
        e.code_postal,
        e.departement,
        COALESCE(e.code_naf_etab, ul.code_naf_ul)  AS code_naf,
        ul.code_categorie_juridique,
        ul.categorie_entreprise,
        ul.tranche_effectifs,
        e.latitude,
        e.longitude,
        -- Nom normalise precalcule pour jointure sans SIRET
        `cartographie-data-engineer.staging.normalize_company_name`(
            COALESCE(e.nom, ul.nom_unite_legale)
        ) AS nom_normalise
    FROM etab e
    LEFT JOIN ul ON e.siren = ul.siren
),

dedup AS (
    SELECT *
    FROM joined
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY siret
        ORDER BY
            nom IS NOT NULL DESC,
            nom_unite_legale IS NOT NULL DESC,
            code_categorie_juridique IS NOT NULL DESC
    ) = 1
)

SELECT * FROM dedup;
