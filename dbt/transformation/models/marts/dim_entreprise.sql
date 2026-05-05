{{ config(materialized='table') }}

--
-- Dimension entreprise — référentiel SIRENE consolidé exposé aux outils BI.
-- 1 ligne par SIRET (clé primaire). Clé secondaire : siren.
--

SELECT
    -- Identifiants
    siret,
    siren,

    -- Nom
    nom                             AS nom_etablissement,
    nom_unite_legale                AS raison_sociale,
    COALESCE(nom, nom_unite_legale) AS nom_affiche,

    -- Localisation
    nom_commune,
    code_postal,
    code_insee,
    departement                     AS code_departement,
    latitude,
    longitude,

    -- Caractéristiques légales
    code_naf,
    code_categorie_juridique,
    categorie_entreprise,           -- PME / ETI / GE
    tranche_effectifs,

    -- Libellé tranche effectifs (utile en BI sans table de correspondance)
    CASE tranche_effectifs
        WHEN '00' THEN '0 salarié'
        WHEN '01' THEN '1 à 2 salariés'
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
        ELSE 'Non renseigné'
    END                             AS libelle_tranche_effectifs,

    -- Segment taille simplifié pour filtres BI
    CASE
        WHEN tranche_effectifs IN ('00', '01', '02', '03') THEN 'TPE (< 10)'
        WHEN tranche_effectifs IN ('11', '12')             THEN 'PME (10-49)'
        WHEN tranche_effectifs IN ('21', '22')             THEN 'PME (50-199)'
        WHEN tranche_effectifs IN ('31', '32')             THEN 'ETI (200-499)'
        WHEN tranche_effectifs IN ('41', '42', '51', '52', '53') THEN 'GE (500+)'
        ELSE 'Inconnu'
    END                             AS segment_taille

FROM {{ ref('int_sirene__entreprises') }}
