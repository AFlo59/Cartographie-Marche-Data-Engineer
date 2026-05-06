{{ config(materialized='table') }}

--
-- Dimension source d'offre — référentiel statique des 3 plateformes.
-- 1 ligne par source. Clé primaire : source_id (= fct_offres.source_offre).
-- Jointure BI : fct_offres.source_offre → dim_source_offre.source_id
--

SELECT
    'france_travail'                AS source_id,
    'France Travail'                AS nom_affiche,
    'Service public emploi'         AS type_source,
    'Tous profils'                  AS perimetre_public,
    'Hebdomadaire (lundi 6h)'       AS frequence_maj,
    'https://www.francetravail.fr'  AS url_site,
    TRUE                            AS est_source_officielle,
    'API officielle France Travail (ex Pôle Emploi). Couverture nationale toutes qualifications. Contient SIRET, code ROME et coordonnées géographiques.'
                                    AS description

UNION ALL

SELECT
    'apec'                          AS source_id,
    'APEC'                          AS nom_affiche,
    'Cadres et dirigeants'          AS type_source,
    'Cadres (BAC+4 / >35 000 €)'   AS perimetre_public,
    'Hebdomadaire (lundi 7h)'       AS frequence_maj,
    'https://www.apec.fr'           AS url_site,
    TRUE                            AS est_source_officielle,
    'Association Pour l\'Emploi des Cadres. Spécialisée postes cadres et ingénieurs. Géocodage intégré à l\'ingestion. Pas de SIRET ni code ROME.'
                                    AS description

UNION ALL

SELECT
    'jooble'                        AS source_id,
    'Jooble'                        AS nom_affiche,
    'Agrégateur international'      AS type_source,
    'Tous profils (multicanal)'     AS perimetre_public,
    'Hebdomadaire (lundi 8h)'       AS frequence_maj,
    'https://fr.jooble.org'         AS url_site,
    FALSE                           AS est_source_officielle,
    'Agrégateur mondial de 140 pays. Consolide les annonces de multiples jobboards. Identifiant entier converti en STRING. Pas de SIRET ni code ROME.'
                                    AS description
