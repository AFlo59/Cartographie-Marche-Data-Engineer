-- ============================================================
-- MODEL : intermediaire.offres
-- Complète le champ `nom` (entreprise) des offres France Travail
-- uniquement pour les lignes où nom IS NULL ou vide.
-- Critères de match (tous requis) :
--   1. DEPARTEMENT identique entre l'offre et l'établissement
--   2. NOM_COMMUNE identique entre l'offre et l'établissement
--   3. Le NOM de l'établissement est contenu dans la DESCRIPTION de l'offre
-- Optimisation : égalités DEPARTEMENT + NOM_COMMUNE en premier (hash join),
-- STRPOS appliqué sur le résidu filtré seulement.
-- En cas de plusieurs matchs, on retient le NOM le plus long (le plus précis).
-- ============================================================

CREATE OR REPLACE TABLE intermediaire.offres AS

WITH

-- Filtrage précoce : uniquement les offres sans nom (réduit le scan dès l'entrée)
null_nom AS (
  SELECT id, description, departement, nom_commune
  FROM staging.offres
  WHERE nom IS NULL OR nom = ''
),

-- Triplets distincts d'établissements localisés
-- On exclut les lignes sans département ou sans commune (inutilisables pour le join)
etab_noms AS (
  SELECT DISTINCT NOM, DEPARTEMENT, NOM_COMMUNE
  FROM staging.etablissements
  WHERE NOM IS NOT NULL AND NOM != ''
    AND DEPARTEMENT  IS NOT NULL
    AND NOM_COMMUNE  IS NOT NULL
),

-- Mise en correspondance en deux étapes ordonnées :
--   Étape 1 — égalité DEPARTEMENT + NOM_COMMUNE : hash join, très sélectif,
--              élimine la quasi-totalité des candidats avant l'étape 2
--   Étape 2 — STRPOS sur la description : coûteux, appliqué sur le résidu seulement
-- QUALIFY retient le NOM le plus long (signal le plus précis) par offre
matched AS (
  SELECT
    o.id,
    e.NOM AS nom_extrait
  FROM null_nom o
  JOIN etab_noms e
    ON  o.departement = e.DEPARTEMENT
    AND o.nom_commune = e.NOM_COMMUNE
    AND STRPOS(o.description, e.NOM) > 0
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY o.id
    ORDER BY LENGTH(e.NOM) DESC
  ) = 1
)

-- Résultat final (toutes les offres) :
-- - nom déjà renseigné  → inchangé  (LEFT JOIN ne trouve pas de match)
-- - nom absent + match  → nom_extrait injecté
-- - nom absent sans match → nom reste NULL
SELECT
  o.* REPLACE(COALESCE(m.nom_extrait, o.nom) AS NOM)
FROM staging.offres o
LEFT JOIN matched m ON o.id = m.id;
