-- =============================================================================
-- 11_mart_dim_date.sql — Dimension calendrier
-- Sortie : cartographie-data-engineer.marts.dim_date
-- Depend : aucune
--
-- Genere chaque jour de 2020-01-01 a 2031-12-31 via GENERATE_DATE_ARRAY.
-- Cle primaire : date_id (DATE) — jointure depuis fct_offres.date_creation.
-- =============================================================================

CREATE OR REPLACE TABLE `cartographie-data-engineer.marts.dim_date`
AS

WITH date_spine AS (
    SELECT date_day
    FROM UNNEST(
        GENERATE_DATE_ARRAY(DATE('2020-01-01'), DATE('2031-12-31'), INTERVAL 1 DAY)
    ) AS date_day
)

SELECT
    date_day                                                            AS date_id,
    date_day                                                            AS date_complete,
    EXTRACT(YEAR    FROM date_day)                                      AS annee,
    EXTRACT(QUARTER FROM date_day)                                      AS trimestre,
    EXTRACT(MONTH   FROM date_day)                                      AS mois_num,
    FORMAT_DATE('%B', date_day)                                         AS nom_mois_en,
    CASE EXTRACT(MONTH FROM date_day)
        WHEN  1 THEN 'Janvier'    WHEN  2 THEN 'Fevrier'
        WHEN  3 THEN 'Mars'       WHEN  4 THEN 'Avril'
        WHEN  5 THEN 'Mai'        WHEN  6 THEN 'Juin'
        WHEN  7 THEN 'Juillet'    WHEN  8 THEN 'Aout'
        WHEN  9 THEN 'Septembre'  WHEN 10 THEN 'Octobre'
        WHEN 11 THEN 'Novembre'   WHEN 12 THEN 'Decembre'
    END                                                                 AS nom_mois_fr,
    EXTRACT(ISOWEEK   FROM date_day)                                    AS semaine_iso,
    EXTRACT(ISOYEAR   FROM date_day)                                    AS annee_semaine_iso,
    EXTRACT(DAYOFYEAR FROM date_day)                                    AS jour_annee,
    EXTRACT(DAY       FROM date_day)                                    AS jour_mois,
    -- 1=Dimanche, 2=Lundi, ..., 7=Samedi (convention BigQuery DAYOFWEEK)
    EXTRACT(DAYOFWEEK FROM date_day)                                    AS jour_semaine_num,
    CASE EXTRACT(DAYOFWEEK FROM date_day)
        WHEN 1 THEN 'Dimanche'  WHEN 2 THEN 'Lundi'
        WHEN 3 THEN 'Mardi'     WHEN 4 THEN 'Mercredi'
        WHEN 5 THEN 'Jeudi'     WHEN 6 THEN 'Vendredi'
        WHEN 7 THEN 'Samedi'
    END                                                                 AS nom_jour_fr,
    CASE EXTRACT(DAYOFWEEK FROM date_day)
        WHEN 1 THEN FALSE WHEN 7 THEN FALSE ELSE TRUE
    END                                                                 AS est_jour_ouvrable,
    FORMAT_DATE('%Y-%m', date_day)                                      AS annee_mois,
    CONCAT(
        CAST(EXTRACT(ISOYEAR FROM date_day) AS STRING),
        '-S',
        LPAD(CAST(EXTRACT(ISOWEEK FROM date_day) AS STRING), 2, '0')
    )                                                                   AS annee_semaine,
    CONCAT(
        CAST(EXTRACT(YEAR FROM date_day) AS STRING),
        '-T',
        CAST(EXTRACT(QUARTER FROM date_day) AS STRING)
    )                                                                   AS annee_trimestre

FROM date_spine;
