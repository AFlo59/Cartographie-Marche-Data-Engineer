{{
    config(
        materialized='incremental',
        unique_key='offre_id',
        incremental_strategy='merge'
    )
}}

--
-- Gold layer APEC : offres enrichies avec géographie et SIRENE.
-- Toutes les colonnes en lowercase_snake_case.
--
-- Spécificités APEC :
--   - latitude/longitude déjà disponibles (geocodage ingestion) → prioritaires
--   - commune et departement extraits par l'ingestion
--   - Pas de SIRET → jointure SIRENE uniquement par nom normalisé + géographie
--   - Pas de code ROME (colonnes NULL)
--

WITH offres AS (
    SELECT * FROM {{ ref('stg_apec__offres') }}
    {% if is_incremental() %}
    WHERE date_insertion >= (
        SELECT COALESCE(MAX(date_insertion) - INTERVAL 7 DAY, DATE('2020-01-01'))
        FROM {{ this }}
    )
    {% endif %}
),

-- Référentiel géo : correspondance commune APEC → code INSEE, région
geo AS (
    SELECT
        CODE_POSTAL                 AS code_postal,
        CODE_INSEE                  AS code_insee,
        NOM                         AS nom_commune_geo,
        DEPARTEMENT                 AS code_departement,
        CODE_REGION                 AS code_region,
        POPULATION
    FROM {{ ref('stg_geo__communes') }}
),

dept AS (
    SELECT
        CODE_DEPARTEMENT            AS code_departement,
        NOM                         AS nom_departement
    FROM {{ ref('stg_geo__departements') }}
),

region AS (
    SELECT
        CODE_REGION                 AS code_region,
        NOM                         AS nom_region
    FROM {{ ref('stg_geo__regions') }}
),

sirene AS (
    SELECT * FROM {{ ref('int_sirene__entreprises') }}
),

-- Enrichissement géo APEC :
-- P1 : commune + département exacts → plus fiable
-- P2 : commune seule (commune dans plusieurs depts)
offres_geo AS (
    SELECT
        o.*,
        COALESCE(g.code_departement, o.departement)     AS departement_final,
        g.code_region,
        g.code_insee,
        CAST(NULL AS STRING)                             AS code_postal,
        ROW_NUMBER() OVER (
            PARTITION BY o.offre_id
            ORDER BY
                CASE
                    WHEN g.nom_commune_geo = o.commune AND g.code_departement = o.departement THEN 1
                    WHEN g.nom_commune_geo = o.commune THEN 2
                    ELSE 3
                END ASC,
                g.POPULATION DESC NULLS LAST
        ) AS rn
    FROM offres o
    LEFT JOIN geo g
        ON g.nom_commune_geo = o.commune
        OR g.code_departement = o.departement
),

offres_geo_dedup AS (
    SELECT * EXCEPT(rn) FROM offres_geo WHERE rn = 1
),

offres_norm AS (
    SELECT
        *,
        {{ normalize_company_name('nom') }} AS nom_normalise
    FROM offres_geo_dedup
),

-- Jointure SIRENE (pas de SIRET APEC → nom + géo uniquement)
sirene_candidates AS (
    SELECT
        o.offre_id,
        s.siret                                         AS siret_sirene,
        s.siren                                         AS siren_sirene,
        COALESCE(s.nom, s.nom_unite_legale)             AS nom_entreprise_sirene,
        s.code_naf,
        s.code_categorie_juridique,
        s.categorie_entreprise,
        s.tranche_effectifs,
        CASE
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                 AND o.code_postal = s.code_postal AND o.code_postal IS NOT NULL
                THEN 2
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                 AND o.code_insee = s.code_insee AND o.code_insee IS NOT NULL
                THEN 3
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                 AND o.departement_final = s.departement AND o.departement_final IS NOT NULL
                THEN 4
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                THEN 5
            ELSE 99
        END AS match_priority
    FROM offres_norm o
    JOIN sirene s ON o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
),

sirene_best AS (
    SELECT *
    FROM sirene_candidates
    WHERE match_priority < 99
    QUALIFY ROW_NUMBER() OVER (PARTITION BY offre_id ORDER BY match_priority ASC) = 1
),

final AS (
    SELECT
        o.offre_id,
        'apec'                                              AS source_offre,
        o.intitule,
        o.description,
        CAST(o.date_publication AS DATE)                    AS date_creation,
        o.date_insertion,

        -- Localisation
        o.code_postal,
        o.code_insee,
        o.commune,
        o.departement_final                                 AS departement,
        d.nom_departement,
        o.code_region,
        r.nom_region,
        -- Coordonnées APEC (geocodage ingestion) prioritaires
        o.latitude,
        o.longitude,

        -- Entreprise source
        o.nom                                               AS nom_entreprise_source,
        CAST(NULL AS STRING)                                AS siret,

        -- Entreprise SIRENE
        s.siret_sirene,
        s.siren_sirene,
        s.nom_entreprise_sirene,
        COALESCE(s.nom_entreprise_sirene, o.nom)            AS nom_entreprise_final,
        s.code_naf,
        s.code_categorie_juridique,
        s.categorie_entreprise,
        s.tranche_effectifs,

        -- Fiabilité jointure SIRENE
        CASE
            WHEN s.match_priority = 2               THEN 'HIGH'
            WHEN s.match_priority IN (3, 4)         THEN 'MEDIUM'
            WHEN s.match_priority = 5               THEN 'LOW'
            ELSE 'NO_MATCH'
        END                                                 AS fiabilite_jointure_sirene,

        -- Contrat
        o.code_contrat,
        o.contract_type_normalized,
        CAST(NULL AS STRING)                                AS type_contrat_libelle,
        CAST(NULL AS NUMERIC)                               AS duree_contrat_mois,

        -- Salaire
        o.salaire_texte_raw                                 AS salaire_texte,
        o.salary_min_annual,
        o.salary_max_annual,
        CAST(NULL AS STRING)                                AS bonus,

        -- Classification métier (non disponible APEC)
        CAST(NULL AS STRING)                                AS code_rome,
        CAST(NULL AS STRING)                                AS appellation,
        CAST(NULL AS STRING)                                AS experience,
        CAST(NULL AS STRING)                                AS qualification,

        -- Pertinence Data Engineering
        o.relevance_score,
        o.matching_confidence,

        CAST(NULL AS STRING)                                AS url

    FROM offres_norm o
    LEFT JOIN sirene_best s     ON o.offre_id = s.offre_id
    LEFT JOIN dept d            ON o.departement_final = d.code_departement
    LEFT JOIN region r          ON o.code_region = r.code_region
)

SELECT * FROM final
