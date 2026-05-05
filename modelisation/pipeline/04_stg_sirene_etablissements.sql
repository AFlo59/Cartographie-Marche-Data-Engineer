-- =============================================================================
-- 04_stg_sirene_etablissements.sql — Staging SIRENE etablissements
-- Source  : cartographie-data-engineer.raw.sirene_etablissements (External Table)
-- Sortie  : cartographie-data-engineer.staging.stg_sirene__etablissements
-- Depend  : 00_udfs.sql
--
-- Note : ~35 millions de lignes. Prevoir un timeout de 3600s dans les settings
--        BigQuery (Menu > Parametres > Timeout de requete).
-- Convention colonnes : UPPERCASE (couche staging SIRENE v1 conservee)
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.staging.stg_sirene__etablissements`
AS

WITH cleanup AS (
    SELECT
        `cartographie-data-engineer.staging.clean_siret_valid`(siret)                                      AS SIRET,
        `cartographie-data-engineer.staging.clean_string`(enseigne1Etablissement)                          AS NOM_1,
        `cartographie-data-engineer.staging.clean_string`(enseigne2Etablissement)                          AS NOM_2,
        `cartographie-data-engineer.staging.clean_string`(enseigne3Etablissement)                          AS NOM_3,
        `cartographie-data-engineer.staging.clean_string`(denominationUsuelleEtablissement)                AS NOM_4,
        `cartographie-data-engineer.staging.clean_string`(codePostalEtablissement)                        AS CODE_POSTAL,
        `cartographie-data-engineer.staging.clean_commune_tokens`(
            `cartographie-data-engineer.staging.clean_string`(libelleCommuneEtablissement)
        )                                                                                                   AS NOM_COMMUNE_1,
        `cartographie-data-engineer.staging.clean_commune_tokens`(
            `cartographie-data-engineer.staging.clean_string`(libelleCommuneEtrangerEtablissement)
        )                                                                                                   AS NOM_COMMUNE_2,
        `cartographie-data-engineer.staging.clean_string`(codeCommuneEtablissement)                       AS CODE_INSEE,
        `cartographie-data-engineer.staging.clean_string`(activitePrincipaleEtablissement)                AS CODE_NAF,
        IF(
            SAFE_CAST(coordonneeLambertAbscisseEtablissement AS FLOAT64) IS NOT NULL
            AND SAFE_CAST(coordonneeLambertOrdonneeEtablissement AS FLOAT64) IS NOT NULL,
            `cartographie-data-engineer.staging.lambert93_to_latlon`(
                SAFE_CAST(coordonneeLambertAbscisseEtablissement AS FLOAT64),
                SAFE_CAST(coordonneeLambertOrdonneeEtablissement AS FLOAT64)
            ),
            NULL
        ) AS coords

    FROM `cartographie-data-engineer.raw.sirene_etablissements`
),

cleanup_flat AS (
    SELECT
        SIRET, NOM_1, NOM_2, NOM_3, NOM_4,
        CODE_POSTAL, NOM_COMMUNE_1, NOM_COMMUNE_2, CODE_INSEE, CODE_NAF,
        coords.lat AS LATITUDE,
        coords.lon AS LONGITUDE,
        COALESCE(
            CASE
                WHEN REGEXP_CONTAINS(COALESCE(CODE_POSTAL, ''), r'^(97[1-6]|98[0-9])\d{2}$') THEN SUBSTR(CODE_POSTAL, 1, 3)
                WHEN REGEXP_CONTAINS(COALESCE(CODE_POSTAL, ''), r'^\d{5}$')                   THEN SUBSTR(CODE_POSTAL, 1, 2)
                ELSE NULL
            END,
            CASE
                WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^2[AB]\d{3}$')               THEN SUBSTR(CODE_INSEE, 1, 2)
                WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^(97[1-6]|98[0-9])\d{2}$')  THEN SUBSTR(CODE_INSEE, 1, 3)
                WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^\d{5}$')                    THEN SUBSTR(CODE_INSEE, 1, 2)
                ELSE NULL
            END
        ) AS DEPARTEMENT
    FROM cleanup
),

-- UNION des variantes de noms x variantes de commune -> table de lookup NOM+LIEU
union_data AS (
    SELECT SIRET, NOM_1 AS NOM, NOM_COMMUNE_1 AS NOM_COMMUNE, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_1 IS NOT NULL AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_2, NOM_COMMUNE_1, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_2 IS NOT NULL AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_3, NOM_COMMUNE_1, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_3 IS NOT NULL AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_4, NOM_COMMUNE_1, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_4 IS NOT NULL AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_1, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_1 IS NOT NULL AND NOM_COMMUNE_2 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_2, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_2 IS NOT NULL AND NOM_COMMUNE_2 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_3, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_3 IS NOT NULL AND NOM_COMMUNE_2 IS NOT NULL
    UNION ALL
    SELECT SIRET, NOM_4, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE FROM cleanup_flat WHERE NOM_4 IS NOT NULL AND NOM_COMMUNE_2 IS NOT NULL
)

SELECT DISTINCT
    SIRET, NOM, NOM_COMMUNE, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, CODE_NAF, LATITUDE, LONGITUDE
FROM union_data;
