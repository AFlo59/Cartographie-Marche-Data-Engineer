{{ config(materialized='table') }}

--
-- Dimension calendrier — couvre 2020-01-01 → 2031-12-31.
-- Génère chaque jour via GENERATE_DATE_ARRAY BigQuery (aucun seed CSV requis).
-- Colonnes principales exploitables par tout outil BI (Looker Studio, Power BI, Metabase…).
--
-- Clé primaire : date_id (DATE) — jointure directe depuis fct_offres.date_creation.
--

WITH date_spine AS (
    SELECT date_day
    FROM UNNEST(
        GENERATE_DATE_ARRAY(DATE('2020-01-01'), DATE('2031-12-31'), INTERVAL 1 DAY)
    ) AS date_day
)

SELECT
    -- Clé primaire
    date_day                                                            AS date_id,
    date_day                                                            AS date_complete,

    -- Décomposition temporelle
    EXTRACT(YEAR    FROM date_day)                                      AS annee,
    EXTRACT(QUARTER FROM date_day)                                      AS trimestre,
    EXTRACT(MONTH   FROM date_day)                                      AS mois_num,
    FORMAT_DATE('%B', date_day)                                         AS nom_mois_en,
    CASE EXTRACT(MONTH FROM date_day)
        WHEN  1 THEN 'Janvier'    WHEN  2 THEN 'Février'
        WHEN  3 THEN 'Mars'       WHEN  4 THEN 'Avril'
        WHEN  5 THEN 'Mai'        WHEN  6 THEN 'Juin'
        WHEN  7 THEN 'Juillet'    WHEN  8 THEN 'Août'
        WHEN  9 THEN 'Septembre'  WHEN 10 THEN 'Octobre'
        WHEN 11 THEN 'Novembre'   WHEN 12 THEN 'Décembre'
    END                                                                 AS nom_mois_fr,

    -- Semaine ISO
    EXTRACT(ISOWEEK FROM date_day)                                      AS semaine_iso,
    EXTRACT(ISOYEAR FROM date_day)                                      AS annee_semaine_iso,

    -- Jour dans l'année et dans le mois
    EXTRACT(DAYOFYEAR FROM date_day)                                    AS jour_annee,
    EXTRACT(DAY       FROM date_day)                                    AS jour_mois,

    -- Jour de semaine (1 = Dimanche, 2 = Lundi, … 7 = Samedi)
    EXTRACT(DAYOFWEEK FROM date_day)                                    AS jour_semaine_num,
    CASE EXTRACT(DAYOFWEEK FROM date_day)
        WHEN 1 THEN 'Dimanche'  WHEN 2 THEN 'Lundi'
        WHEN 3 THEN 'Mardi'     WHEN 4 THEN 'Mercredi'
        WHEN 5 THEN 'Jeudi'     WHEN 6 THEN 'Vendredi'
        WHEN 7 THEN 'Samedi'
    END                                                                 AS nom_jour_fr,

    -- Indicateurs
    CASE EXTRACT(DAYOFWEEK FROM date_day)
        WHEN 1 THEN FALSE WHEN 7 THEN FALSE ELSE TRUE
    END                                                                 AS est_jour_ouvrable,

    -- Libellés agrégats utiles en BI
    FORMAT_DATE('%Y-%m', date_day)                                      AS annee_mois,       -- "2024-06"
    CONCAT(
        CAST(EXTRACT(ISOYEAR FROM date_day) AS STRING),
        '-S',
        LPAD(CAST(EXTRACT(ISOWEEK FROM date_day) AS STRING), 2, '0')
    )                                                                   AS annee_semaine,    -- "2024-S23"
    CONCAT(
        CAST(EXTRACT(YEAR FROM date_day) AS STRING),
        '-T',
        CAST(EXTRACT(QUARTER FROM date_day) AS STRING)
    )                                                                   AS annee_trimestre   -- "2024-T2"

FROM date_spine
