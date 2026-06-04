{{ config(materialized='table', job_execution_timeout_seconds=3600) }}

WITH cleanup AS (
    SELECT
        {{ clean_siret_valid('siret') }}                                                AS SIRET,
        {{ clean_string('enseigne1Etablissement') }}                                    AS NOM_1,
        {{ clean_string('enseigne2Etablissement') }}                                    AS NOM_2,
        {{ clean_string('enseigne3Etablissement') }}                                    AS NOM_3,
        {{ clean_string('denominationUsuelleEtablissement') }}                          AS NOM_4,
        {{ clean_string('codePostalEtablissement') }}                                   AS CODE_POSTAL,
        {{ clean_commune_tokens(clean_string('libelleCommuneEtablissement')) }}         AS NOM_COMMUNE_1,
        {{ clean_commune_tokens(clean_string('libelleCommuneEtrangerEtablissement')) }} AS NOM_COMMUNE_2,
        {{ clean_string('codeCommuneEtablissement') }}                                  AS CODE_INSEE,
        {{ clean_string('activitePrincipaleEtablissement') }}                            AS CODE_NAF,
        IF(
            SAFE_CAST(coordonneeLambertAbscisseEtablissement AS FLOAT64) IS NOT NULL
            AND SAFE_CAST(coordonneeLambertOrdonneeEtablissement AS FLOAT64) IS NOT NULL,
            {{ lambert93_to_latlon(
                'coordonneeLambertAbscisseEtablissement',
                'coordonneeLambertOrdonneeEtablissement'
            ) }},
            NULL
        ) AS coords
    FROM {{ source('raw', 'sirene_etablissements') }}
),

cleanup_flat AS (
    SELECT
        SIRET, NOM_1, NOM_2, NOM_3, NOM_4,
        CODE_POSTAL, NOM_COMMUNE_1, NOM_COMMUNE_2, CODE_INSEE, CODE_NAF,
        coords.lat AS LATITUDE,
        coords.lon AS LONGITUDE,
        -- Département déduit du code postal (prioritaire) puis du code INSEE (2A/2B)
        COALESCE(
            CASE
                WHEN REGEXP_CONTAINS(COALESCE(CODE_POSTAL, ''), r'^(97[1-6]|98[0-9])\d{2}$') THEN SUBSTR(CODE_POSTAL, 1, 3)
                WHEN REGEXP_CONTAINS(COALESCE(CODE_POSTAL, ''), r'^\d{5}$')                   THEN SUBSTR(CODE_POSTAL, 1, 2)
                ELSE NULL
            END,
            CASE
                WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^2[AB]\d{3}$')              THEN SUBSTR(CODE_INSEE, 1, 2)
                WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^(97[1-6]|98[0-9])\d{2}$') THEN SUBSTR(CODE_INSEE, 1, 3)
                WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^\d{5}$')                   THEN SUBSTR(CODE_INSEE, 1, 2)
                ELSE NULL
            END
        ) AS DEPARTEMENT
    FROM cleanup
)

-- Unpivot des 4 variantes de nom × 2 variantes de commune → lookup NOM+LIEU.
-- UNNEST déplie les 8 combinaisons EN MÉMOIRE : cleanup_flat (donc l'external
-- Sirene) n'est lu qu'UNE fois. Les anciens 8 UNION ALL re-scannaient la table
-- externe 8× (≈ 67 GiB/run → ~8 GiB). Sortie strictement identique.
SELECT DISTINCT
    SIRET,
    nom         AS NOM,
    commune     AS NOM_COMMUNE,
    CODE_INSEE,
    CODE_POSTAL,
    DEPARTEMENT,
    CODE_NAF,
    LATITUDE,
    LONGITUDE
FROM cleanup_flat,
     UNNEST([NOM_1, NOM_2, NOM_3, NOM_4])   AS nom,
     UNNEST([NOM_COMMUNE_1, NOM_COMMUNE_2]) AS commune
WHERE nom IS NOT NULL
  AND commune IS NOT NULL
