WITH raw_jooble AS (
  SELECT *,
    LOWER(title) as clean_title,
    LOWER(snippet) as clean_desc
  FROM `cartographie-data-engineer.raw.jooble_offres`
  WHERE dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
),

-- CTE de référence pour identifier les exclusions (Régions/Départements)
geo_exclusions AS (
  SELECT UPPER(TRIM(NORMALIZE(nom, NFD))) as geo_label 
  FROM `cartographie-data-engineer.raw.geo_departements`
  WHERE UPPER(TRIM(NORMALIZE(nom, NFD))) NOT IN ('PARIS', 'LYON', 'MARSEILLE')
  
  UNION DISTINCT
  
  SELECT UPPER(TRIM(NORMALIZE(nom, NFD))) as geo_label 
  FROM `cartographie-data-engineer.raw.geo_regions`
),

processed_jooble AS (
  SELECT 
    CAST(jooble_id AS STRING) as source_id,
    'jooble' as source_name,
    
    -- 1. TITRE NETTOYÉ (Sans Emojis, sans scories Jooble, garde les accents)
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(title, r'(?i) Ajouter aux favoris|[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]', ''), 
      r'\s{2,}', ' '
    )) as title,

    -- 2. DESCRIPTION NETTOYÉE (Sans Emojis, sans sauts de ligne, garde les accents)
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(REPLACE(snippet, r'\u0027', "'"), r'[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]', ''),
        r'[\t\n\r]+', ' '
      ),
      r'\s{2,}', ' '
    )) as description,

    COALESCE(company, 'Confidentiel') as company_name,
    TIMESTAMP_MICROS(DIV(updated_dt, 1000)) as published_at,
    DATE(TIMESTAMP_MICROS(DIV(updated_dt, 1000))) as published_date,
    salary as salary_raw,
    location as location_raw,

    -- 3. NORMALISATION DE LA VILLE
    UPPER(TRIM(
      REGEXP_REPLACE(
        NORMALIZE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(IF(CONTAINS_SUBSTR(location, ','), SPLIT(location, ',')[OFFSET(0)], location), r'\(.*\)|[0-9]{5}', ''),
            r'(?i)^(canton de |arrondissement de |commune de |ville de |ville d\'|arrondissement d\')', ''
          ), 
          NFD
        ), 
        r"[\pM]|(?i)[0-9]+(?:er|e|eme)\b|[0-9]|ARRONDISSEMENT|CEDEX", ""
      )
    )) as city_name_norm_raw,

    -- 4. LOGIQUE CONTRAT HARMONISÉE
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(title || ' ' || snippet), r'alternance|apprentissage|alternant|professionnalisation') THEN 'Alternance'
      WHEN REGEXP_CONTAINS(LOWER(title || ' ' || snippet), r'stagiaire|stage') THEN 'Stage'
      WHEN REGEXP_CONTAINS(LOWER(title), r'freelance|indépendant') 
           OR REGEXP_CONTAINS(LOWER(salary), r'€/jour|tjm') THEN 'Freelance'
      WHEN REGEXP_CONTAINS(LOWER(title || ' ' || snippet), r'cdd|intérim|durée déterminée') THEN 'CDD'
      ELSE 'CDI' 
    END as contract_type,

    -- 5. LOGIQUE SALAIRE MULTIPLIER (Ajustée pour le Freelance)
    CASE 
      WHEN (REGEXP_CONTAINS(LOWER(title), r'freelance') OR REGEXP_CONTAINS(LOWER(salary), r'€/jour|tjm')) THEN 1
      WHEN REGEXP_CONTAINS(salary, r'(?i)mois|mensuel') THEN 12
      WHEN SAFE_CAST(REGEXP_EXTRACT(REPLACE(salary, ' ', ''), r'([0-9]+)') AS INT64) < 5000 
           AND NOT REGEXP_CONTAINS(LOWER(salary), r'[0-9]k') THEN 12
      ELSE 1
    END as salary_multiplier,

    (CASE WHEN REGEXP_CONTAINS(LOWER(title), r'(data.*engineer|ingénieur.*data|data.*analyst)') THEN 15 ELSE 0 END) as relevance_score,
    UPPER(REGEXP_REPLACE(NORMALIZE(company, NFD), r"[^\w]", "")) as company_key

  FROM raw_jooble
  QUALIFY ROW_NUMBER() OVER(PARTITION BY jooble_id ORDER BY dt DESC) = 1
),

salary_parsing AS (
  SELECT 
    p.*,
    SAFE_CAST(
      REGEXP_REPLACE(
        REGEXP_REPLACE(REGEXP_EXTRACT(REPLACE(LOWER(salary_raw), ' ', ''), r'([0-9]+[\.,]?[0-9]*k?)'), r',', '.'), 
        r'k', '000'
      ) AS FLOAT64) * (CASE WHEN REGEXP_CONTAINS(LOWER(salary_raw), r'k') AND REGEXP_CONTAINS(salary_raw, r'[\.,]') THEN 0.001 ELSE 1 END) as s1,
    
    SAFE_CAST(
      REGEXP_REPLACE(
        REGEXP_REPLACE(REGEXP_EXTRACT(REPLACE(LOWER(salary_raw), ' ', ''), r'[aà]([0-9]+[\.,]?[0-9]*k?)'), r',', '.'), 
        r'k', '000'
      ) AS FLOAT64) * (CASE WHEN REGEXP_CONTAINS(LOWER(salary_raw), r'k') AND REGEXP_CONTAINS(salary_raw, r'[\.,]') THEN 0.001 ELSE 1 END) as s2
  FROM processed_jooble p
)

SELECT 
  s.* EXCEPT(relevance_score, s1, s2, salary_multiplier, city_name_norm_raw),
  
  CASE 
    WHEN ex.geo_label IS NOT NULL THEN NULL 
    ELSE s.city_name_norm_raw 
  END as city_name_norm,

  CAST(s1 * salary_multiplier AS INT64) as salary_min,
  CAST(COALESCE(s2, s1) * salary_multiplier AS INT64) as salary_max,
  CASE WHEN relevance_score >= 15 THEN 'High' ELSE 'Low' END as matching_confidence
FROM salary_parsing s
LEFT JOIN geo_exclusions ex ON s.city_name_norm_raw = ex.geo_label
WHERE relevance_score > 0 
AND (s.city_name_norm_raw NOT IN ('FRANCE', 'EUROPE', 'USA', 'TELETRAVAIL'))
AND s.city_name_norm_raw != ''