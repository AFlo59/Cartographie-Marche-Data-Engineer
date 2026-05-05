-- =============================================================================
-- 08_int_france_travail_enrichie.sql — Gold layer France Travail
-- Source  : staging.stg_france_travail__offres + stg_geo__* + intermediate.int_sirene__entreprises
-- Sortie  : cartographie-data-engineer.intermediate.int_france_travail__enrichie
-- Depend  : 01..06 staging + 07_int_sirene_entreprises.sql
--
-- Enrichissement geographique depuis le referentiel geo (code_postal -> commune/dept/region).
-- Jointure SIRENE multi-priorite :
--   P1 : SIRET exact                         -> fiabilite HIGH
--   P2 : nom_normalise + code_postal          -> fiabilite HIGH
--   P3 : nom_normalise + code_insee           -> fiabilite MEDIUM
--   P4 : nom_normalise + departement          -> fiabilite MEDIUM
--   P5 : nom_normalise seul                   -> fiabilite LOW
--   P99 : aucun match                         -> fiabilite NO_MATCH
-- Company name recovery : cherche le nom SIRENE dans la description si nom absent.
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.intermediate.int_france_travail__enrichie`
AS

WITH offres AS (
    SELECT * FROM `cartographie-data-engineer.staging.stg_france_travail__offres`
),

-- Referentiel geo : 1 ligne par code_postal (commune la plus peuplee)
geo AS (
    SELECT
        CODE_POSTAL      AS code_postal,
        CODE_INSEE       AS code_insee,
        NOM              AS nom_commune_geo,
        DEPARTEMENT      AS code_departement,
        CODE_REGION      AS code_region,
        LATITUDE         AS geo_latitude,
        LONGITUDE        AS geo_longitude,
        POPULATION
    FROM `cartographie-data-engineer.staging.stg_geo__communes`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CODE_POSTAL ORDER BY POPULATION DESC NULLS LAST) = 1
),

dept AS (
    SELECT CODE_DEPARTEMENT AS code_departement, NOM AS nom_departement
    FROM `cartographie-data-engineer.staging.stg_geo__departements`
),

region AS (
    SELECT CODE_REGION AS code_region, NOM AS nom_region
    FROM `cartographie-data-engineer.staging.stg_geo__regions`
),

sirene AS (
    SELECT * FROM `cartographie-data-engineer.intermediate.int_sirene__entreprises`
),

offres_geo AS (
    SELECT
        o.*,
        COALESCE(g.nom_commune_geo, o.nom_commune) AS commune_finale,
        COALESCE(g.code_departement, o.departement) AS departement_final,
        g.code_region,
        g.geo_latitude  AS latitude,
        g.geo_longitude AS longitude
    FROM offres o
    LEFT JOIN geo g ON o.code_postal = g.code_postal
),

offres_norm AS (
    SELECT
        *,
        `cartographie-data-engineer.staging.normalize_company_name`(nom) AS nom_normalise
    FROM offres_geo
),

-- Candidats SIRENE avec priorite de correspondance
sirene_candidates AS (
    SELECT
        o.offre_id,
        s.siret                              AS siret_sirene,
        s.siren                              AS siren_sirene,
        COALESCE(s.nom, s.nom_unite_legale)  AS nom_entreprise_sirene,
        s.code_naf,
        s.code_categorie_juridique,
        s.categorie_entreprise,
        s.tranche_effectifs,
        CASE
            WHEN o.siret IS NOT NULL AND o.siret = s.siret                                           THEN 1
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                 AND o.code_postal = s.code_postal AND o.code_postal IS NOT NULL                     THEN 2
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                 AND o.code_insee = s.code_insee AND o.code_insee IS NOT NULL                        THEN 3
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise
                 AND o.departement_final = s.departement AND o.departement_final IS NOT NULL         THEN 4
            WHEN o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise                   THEN 5
            ELSE 99
        END AS match_priority
    FROM offres_norm o
    JOIN sirene s
        ON  o.siret = s.siret
        OR (o.nom_normalise IS NOT NULL AND o.nom_normalise = s.nom_normalise)
),

sirene_best AS (
    SELECT *
    FROM sirene_candidates
    WHERE match_priority < 99
    QUALIFY ROW_NUMBER() OVER (PARTITION BY offre_id ORDER BY match_priority ASC) = 1
),

-- Company name recovery : offres sans nom -> recherche SIRENE dans la description
company_recovery AS (
    SELECT
        o.offre_id,
        s.nom AS nom_recupere,
        ROW_NUMBER() OVER (PARTITION BY o.offre_id ORDER BY LENGTH(s.nom) DESC) AS rn
    FROM offres_norm o
    JOIN sirene s
        ON  o.departement_final = s.departement
        AND (o.commune_finale = s.nom_commune OR o.nom_commune = s.nom_commune)
        AND o.description IS NOT NULL
        AND STRPOS(o.description, s.nom) > 0
    WHERE (o.nom IS NULL OR o.nom = '')
      AND s.nom IS NOT NULL
      AND LENGTH(s.nom) >= 3
),

company_recovery_best AS (
    SELECT offre_id, nom_recupere FROM company_recovery WHERE rn = 1
),

final AS (
    SELECT
        o.offre_id,
        'france_travail'                                    AS source_offre,
        o.intitule,
        o.description,
        CAST(o.date_creation AS DATE)                       AS date_creation,
        o.date_insertion,
        o.code_postal,
        o.code_insee,
        o.commune_finale                                    AS commune,
        o.departement_final                                 AS departement,
        d.nom_departement,
        o.code_region,
        r.nom_region,
        o.latitude,
        o.longitude,
        COALESCE(o.nom, cr.nom_recupere)                    AS nom_entreprise_source,
        o.siret,
        s.siret_sirene,
        s.siren_sirene,
        s.nom_entreprise_sirene,
        COALESCE(s.nom_entreprise_sirene, o.nom, cr.nom_recupere) AS nom_entreprise_final,
        s.code_naf,
        s.code_categorie_juridique,
        s.categorie_entreprise,
        s.tranche_effectifs,
        CASE
            WHEN s.match_priority IN (1, 2) THEN 'HIGH'
            WHEN s.match_priority IN (3, 4) THEN 'MEDIUM'
            WHEN s.match_priority = 5       THEN 'LOW'
            WHEN cr.nom_recupere IS NOT NULL THEN 'RECOVERED'
            ELSE 'NO_MATCH'
        END                                                 AS fiabilite_jointure_sirene,
        o.code_contrat,
        o.contract_type_normalized,
        o.contrat.type_contrat                              AS type_contrat_libelle,
        o.contrat.duree_mois                                AS duree_contrat_mois,
        o.salaire_texte_raw                                 AS salaire_texte,
        o.salary_min_annual,
        o.salary_max_annual,
        o.bonus,
        o.code_rome,
        o.appellation,
        o.experience,
        o.qualification,
        o.relevance_score,
        o.matching_confidence,
        CAST(NULL AS STRING)                                AS url
    FROM offres_norm o
    LEFT JOIN sirene_best s            ON o.offre_id = s.offre_id
    LEFT JOIN company_recovery_best cr ON o.offre_id = cr.offre_id
    LEFT JOIN dept d                   ON o.departement_final = d.code_departement
    LEFT JOIN region r                 ON o.code_region = r.code_region
)

SELECT * FROM final;
