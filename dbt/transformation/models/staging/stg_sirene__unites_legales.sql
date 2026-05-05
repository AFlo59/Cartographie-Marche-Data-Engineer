{{ config(materialized='table') }}

WITH cleanup AS (
    SELECT
        -- SIREN : padding à 9 chiffres (SIRENE stocke parfois sans zéros initiaux)
        LPAD(TRIM(COALESCE(siren, '')), 9, '0')                                         AS SIREN,

        -- Nom : personnes morales → denominationUniteLegale
        --       personnes physiques → prénom + nom de famille
        {{ clean_string(
            "CASE
                WHEN denominationUniteLegale IS NOT NULL AND TRIM(denominationUniteLegale) != ''
                    THEN denominationUniteLegale
                WHEN nomUniteLegale IS NOT NULL AND prenomUsuelUniteLegale IS NOT NULL
                    THEN CONCAT(prenomUsuelUniteLegale, ' ', nomUniteLegale)
                WHEN nomUniteLegale IS NOT NULL
                    THEN nomUniteLegale
                ELSE NULL
            END"
        ) }}                                                                              AS NOM_COMPLET,

        -- Code NAF de l'unité légale (peut différer de celui de l'établissement)
        {{ clean_string('activitePrincipaleUniteLegale') }}                              AS CODE_NAF,

        -- Code catégorie juridique (ex: 5710 = SA, 5499 = SARL, 1000 = personne phys.)
        UPPER(TRIM(COALESCE(categorieJuridiqueUniteLegale, '')))                         AS CODE_CATEGORIE_JURIDIQUE,

        -- Catégorie entreprise INSEE : PME / ETI / GE (nullable)
        UPPER(TRIM(COALESCE(categorieEntreprise, '')))                                   AS CATEGORIE_ENTREPRISE,

        -- Tranche effectifs (00=0, 01=1-2, 11=10-19, 21=20-49, … 53=10000+, NN=non renseigné)
        UPPER(TRIM(COALESCE(trancheEffectifsUniteLegale, '')))                           AS TRANCHE_EFFECTIFS,

        etatAdministratifUniteLegale                                                      AS ETAT_ADMINISTRATIF,
        statutDiffusionUniteLegale                                                        AS STATUT_DIFFUSION

    FROM {{ source('raw', 'sirene_unites_legales') }}
    WHERE etatAdministratifUniteLegale = 'A'   -- actives uniquement
      AND statutDiffusionUniteLegale   = 'O'   -- diffusibles (hors personnes non consentantes)
),

dedup AS (
    SELECT
        SIREN,
        NOM_COMPLET,
        CODE_NAF,
        CODE_CATEGORIE_JURIDIQUE,
        CATEGORIE_ENTREPRISE,
        TRANCHE_EFFECTIFS
    FROM cleanup
    WHERE SIREN IS NOT NULL AND SIREN != ''
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY SIREN
        ORDER BY NOM_COMPLET NULLS LAST
    ) = 1
)

SELECT * FROM dedup
