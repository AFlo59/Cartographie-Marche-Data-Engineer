-- =============================================================================
-- 05_stg_sirene_unites_legales.sql — Staging SIRENE unites legales
-- Source  : cartographie-data-engineer.raw.sirene_unites_legales (External Table)
-- Sortie  : cartographie-data-engineer.staging.stg_sirene__unites_legales
-- Depend  : 00_udfs.sql
-- Filtre  : actives (A) + diffusibles (O) uniquement
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_sirene__unites_legales`
AS

WITH cleanup AS (
    SELECT
        -- SIREN : padding a 9 chiffres (SIRENE stocke parfois sans zeros initiaux)
        LPAD(TRIM(COALESCE(siren, '')), 9, '0') AS SIREN,

        -- Nom : personnes morales -> denominationUniteLegale
        --       personnes physiques -> prenom + nom de famille
        `cartographie-data-engineer.staging.clean_string`(
            CASE
                WHEN denominationUniteLegale IS NOT NULL AND TRIM(denominationUniteLegale) != ''
                    THEN denominationUniteLegale
                WHEN nomUniteLegale IS NOT NULL AND prenomUsuelUniteLegale IS NOT NULL
                    THEN CONCAT(prenomUsuelUniteLegale, ' ', nomUniteLegale)
                WHEN nomUniteLegale IS NOT NULL
                    THEN nomUniteLegale
                ELSE NULL
            END
        ) AS NOM_COMPLET,

        `cartographie-data-engineer.staging.clean_string`(activitePrincipaleUniteLegale) AS CODE_NAF,
        UPPER(TRIM(COALESCE(categorieJuridiqueUniteLegale, '')))                          AS CODE_CATEGORIE_JURIDIQUE,
        UPPER(TRIM(COALESCE(categorieEntreprise, '')))                                    AS CATEGORIE_ENTREPRISE,
        UPPER(TRIM(COALESCE(trancheEffectifsUniteLegale, '')))                            AS TRANCHE_EFFECTIFS

    FROM `cartographie-data-engineer.raw.sirene_unites_legales`
    WHERE etatAdministratifUniteLegale = 'A'
      AND statutDiffusionUniteLegale   = 'O'
),

dedup AS (
    SELECT
        SIREN, NOM_COMPLET, CODE_NAF, CODE_CATEGORIE_JURIDIQUE, CATEGORIE_ENTREPRISE, TRANCHE_EFFECTIFS
    FROM cleanup
    WHERE SIREN IS NOT NULL AND SIREN != ''
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY SIREN
        ORDER BY NOM_COMPLET NULLS LAST
    ) = 1
)

SELECT * FROM dedup;
