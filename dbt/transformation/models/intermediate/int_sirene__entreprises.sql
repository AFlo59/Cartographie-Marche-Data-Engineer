{{
    config(
        materialized='table',
        job_execution_timeout_seconds=3600
    )
}}

--
-- Table de référence SIRENE consolidée : 1 ligne par SIRET actif.
-- Joint l'établissement (coordonnées, NAF local) avec l'unité légale (raison sociale,
-- catégorie juridique, taille) sur le SIREN commun.
-- Pré-calcule nom_normalise pour jointure rapide sur nom d'entreprise dans les offres.
--
-- Convention : toutes les colonnes en lowercase_snake_case (normalisation couche intermediate).
-- Les colonnes sources stg_sirene__etablissements (UPPERCASE) sont réaliasées ici.
--

WITH etab AS (
    SELECT
        SIRET                       AS siret,
        SUBSTR(SIRET, 1, 9)         AS siren,
        NOM                         AS nom,
        NOM_COMMUNE                 AS nom_commune,
        CODE_INSEE                  AS code_insee,
        CODE_POSTAL                 AS code_postal,
        DEPARTEMENT                 AS departement,
        CODE_NAF                    AS code_naf_etab,
        LATITUDE                    AS latitude,
        LONGITUDE                   AS longitude
    FROM {{ ref('stg_sirene__etablissements') }}
    WHERE SIRET IS NOT NULL
),

ul AS (
    SELECT
        siren,
        nom_complet                 AS nom_unite_legale,
        code_naf                    AS code_naf_ul,
        code_categorie_juridique,
        categorie_entreprise,
        tranche_effectifs
    FROM {{ ref('stg_sirene__unites_legales') }}
),

joined AS (
    SELECT
        e.siret,
        e.siren,

        -- Nom : enseigne établissement en priorité, sinon raison sociale unité légale
        COALESCE(e.nom, ul.nom_unite_legale)            AS nom,
        ul.nom_unite_legale,

        e.nom_commune,
        e.code_insee,
        e.code_postal,
        e.departement,

        -- NAF établissement prioritaire (plus précis), sinon NAF UL
        COALESCE(e.code_naf_etab, ul.code_naf_ul)      AS code_naf,

        ul.code_categorie_juridique,
        ul.categorie_entreprise,        -- PME / ETI / GE
        ul.tranche_effectifs,

        e.latitude,
        e.longitude,

        -- Nom normalisé pré-calculé pour jointure sans SIRET
        {{ normalize_company_name('COALESCE(e.nom, ul.nom_unite_legale)') }}  AS nom_normalise

    FROM etab e
    LEFT JOIN ul ON e.siren = ul.siren
),

-- 1 ligne par SIRET : garde la combinaison la mieux renseignée
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

SELECT * FROM dedup
