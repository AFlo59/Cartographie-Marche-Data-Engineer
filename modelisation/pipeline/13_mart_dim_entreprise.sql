-- =============================================================================
-- 13_mart_dim_entreprise.sql — Dimension entreprise (referentiel SIRENE)
-- Source  : intermediate.int_sirene__entreprises
-- Sortie  : cartographie-data-engineer.marts.dim_entreprise
-- Depend  : 07_int_sirene_entreprises.sql
--
-- 1 ligne par SIRET (etablissement). Cle secondaire : siren (unite legale).
-- Enrichi des libelles metier : tranche effectifs, segment taille.
-- Jointure depuis fct_offres.siret_sirene -> dim_entreprise.siret.
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.marts.dim_entreprise`
AS

SELECT
    siret,
    siren,
    nom                                 AS nom_etablissement,
    nom_unite_legale                    AS raison_sociale,
    COALESCE(nom, nom_unite_legale)     AS nom_affiche,
    nom_commune,
    code_postal,
    code_insee,
    departement                         AS code_departement,
    latitude,
    longitude,
    code_naf,
    code_categorie_juridique,
    categorie_entreprise,
    tranche_effectifs,

    -- Libelle lisible de la tranche effectifs (utile en BI sans table de correspondance)
    CASE tranche_effectifs
        WHEN '00' THEN '0 salarie'
        WHEN '01' THEN '1 a 2 salaries'
        WHEN '02' THEN '3 a 5 salaries'
        WHEN '03' THEN '6 a 9 salaries'
        WHEN '11' THEN '10 a 19 salaries'
        WHEN '12' THEN '20 a 49 salaries'
        WHEN '21' THEN '50 a 99 salaries'
        WHEN '22' THEN '100 a 199 salaries'
        WHEN '31' THEN '200 a 249 salaries'
        WHEN '32' THEN '250 a 499 salaries'
        WHEN '41' THEN '500 a 999 salaries'
        WHEN '42' THEN '1 000 a 1 999 salaries'
        WHEN '51' THEN '2 000 a 4 999 salaries'
        WHEN '52' THEN '5 000 a 9 999 salaries'
        WHEN '53' THEN '10 000 salaries et plus'
        ELSE 'Non renseigne'
    END                                 AS libelle_tranche_effectifs,

    -- Segment taille simplifie pour filtres BI
    CASE
        WHEN tranche_effectifs IN ('00', '01', '02', '03') THEN 'TPE (< 10)'
        WHEN tranche_effectifs IN ('11', '12')             THEN 'PME (10-49)'
        WHEN tranche_effectifs IN ('21', '22')             THEN 'PME (50-199)'
        WHEN tranche_effectifs IN ('31', '32')             THEN 'ETI (200-499)'
        WHEN tranche_effectifs IN ('41', '42', '51', '52', '53') THEN 'GE (500+)'
        ELSE 'Inconnu'
    END                                 AS segment_taille

FROM `cartographie-data-engineer.intermediate.int_sirene__entreprises`;
