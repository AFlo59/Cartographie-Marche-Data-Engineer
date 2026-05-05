WITH raw_data AS (
  SELECT *, LOWER(intitule) as clean_title, LOWER(description) as clean_desc
  FROM `cartographie-data-engineer.raw.france_travail_offres`
  WHERE dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
),

geo_exclusions AS (
  SELECT UPPER(TRIM(NORMALIZE(nom, NFD))) as geo_label 
  FROM `cartographie-data-engineer.raw.geo_departements`
  WHERE UPPER(TRIM(NORMALIZE(nom, NFD))) NOT IN ('PARIS', 'LYON', 'MARSEILLE')
  UNION DISTINCT
  SELECT UPPER(TRIM(NORMALIZE(nom, NFD))) as geo_label 
  FROM `cartographie-data-engineer.raw.geo_regions`
),

processed_data AS (
  SELECT 
    id as source_id,
    'france_travail' as source_name,
    
    -- Nettoyage Title
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(intitule, r'[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]', ''), 
      r'\s{2,}', ' '
    )) as title,

    -- Nettoyage Description
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(REPLACE(description, r'\u0027', "'"), r'[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]', ''),
        r'[\t\n\r]+', ' '
      ),
      r'\s{2,}', ' '
    )) as description,

    COALESCE(entreprise_nom, 'Confidentiel') as company_name,
    TIMESTAMP_MICROS(DIV(dateCreation, 1000)) as published_at,
    DATE(TIMESTAMP_MICROS(DIV(dateCreation, 1000))) as published_date,
    salaire_libelle as salary_raw,
    lieuTravail_libelle as location_raw,
    typeContratLibelle as contract_type_raw, -- Ajouté pour la logique de contrat
    REGEXP_EXTRACT(lieuTravail_libelle, r'^([0-9]{2,3})') as department_code,
    
    -- Normalisation de la Ville
    UPPER(TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_EXTRACT(lieuTravail_libelle, r' - (.*)'), 
          r'(?i)[0-9]+(?:er|e|eme)\b|ARRONDISSEMENT|CEDEX', ''
        ),
        r'[^\p{L}\s-]', '' 
      )
    )) as city_name_raw,
    
    SAFE_CAST(NULL AS FLOAT64) as latitude,
    SAFE_CAST(NULL AS FLOAT64) as longitude,

    -- Logique de Score de pertinence
    (
      CASE WHEN REGEXP_CONTAINS(LOWER(intitule), r'(data engineer|ingénieur.*donnée|data ingé|analytics engineer|etl|bi|data warehouse|architecte.*donnée)') THEN 7 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(LOWER(description), r'(spark|airflow|kafka|snowflake|bigquery|dbt|databricks|fivetran|matillion)') THEN 4 ELSE 0 END -
      CASE WHEN REGEXP_CONTAINS(LOWER(intitule), r'(technicien|maintenance|système|réseau|industriel|commercial|achat|sav|chantier|comptable)') AND NOT REGEXP_CONTAINS(LOWER(intitule), r'(data|donnée|etl)') THEN 10 ELSE 0 END
    ) as relevance_score,
    UPPER(REGEXP_REPLACE(NORMALIZE(entreprise_nom, NFD), r"[^\w]", "")) as company_key
  FROM raw_data
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id ORDER BY dt DESC) = 1
),

salary_and_contract_parsing AS (
  SELECT *,
    -- 1. Logique Contrat Affinée
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(title), r'\balternance\b|\bapprentissage\b|\bapprenti\b|\bcontrat pro\b') THEN 'Alternance'
      WHEN REGEXP_CONTAINS(LOWER(title), r'\bstage\b|\bstagiaire\b|\bpfe\b') THEN 'Stage'
      WHEN REGEXP_CONTAINS(LOWER(title), r'\bfreelance\b|\bindépendant\b|\bindependant\b') THEN 'Freelance'
      WHEN REGEXP_CONTAINS(LOWER(description), r'contrat d.apprentissage|en alternance|contrat de professionnalisation') THEN 'Alternance'
      WHEN contract_type_raw = 'CDI' OR REGEXP_CONTAINS(LOWER(contract_type_raw), r'(indéterminé|indetermine)') THEN 'CDI'
      WHEN REGEXP_CONTAINS(LOWER(contract_type_raw), r'intérim|interim|cdd|temporaire') THEN 'CDD/Intérim'
      ELSE 'CDI' 
    END as contract_type,

    -- 2. Logique Salaire
    SAFE_CAST(REGEXP_EXTRACT(REPLACE(salary_raw, ' ', ''), r'([0-9]+(?:\.[0-9]+)?)') AS FLOAT64) as raw_sal_1,
    SAFE_CAST(REGEXP_EXTRACT(REPLACE(salary_raw, ' ', ''), r'à([0-9]+(?:\.[0-9]+)?)') AS FLOAT64) as raw_sal_2,
    
    CASE 
      WHEN salary_raw LIKE 'Mensuel%' AND SAFE_CAST(REGEXP_EXTRACT(REPLACE(salary_raw, ' ', ''), r'([0-9]+)') AS FLOAT64) > 10000 THEN 1
      WHEN salary_raw LIKE 'Annuel%' THEN 1 
      WHEN salary_raw LIKE 'Mensuel%' THEN 12 
      WHEN salary_raw LIKE 'Horaire%' THEN 1820 
      ELSE NULL 
    END as salary_multiplier
  FROM processed_data
)

-- 3. JOIN FINAL AVEC EXCLUSIONS
SELECT 
    s.* EXCEPT(relevance_score, raw_sal_1, raw_sal_2, salary_multiplier, city_name_raw, contract_type_raw),
    
    CASE 
        WHEN ex.geo_label IS NOT NULL THEN NULL 
        ELSE s.city_name_raw 
    END as city_name_norm,

    CAST(CEIL(raw_sal_1 * salary_multiplier) AS INT64) as salary_min,
    CAST(CEIL(COALESCE(raw_sal_2, raw_sal_1) * salary_multiplier) AS INT64) as salary_max,
    CASE WHEN relevance_score >= 7 THEN 'High' WHEN relevance_score BETWEEN 3 AND 6 THEN 'Medium' ELSE 'Low' END as matching_confidence
FROM salary_and_contract_parsing s
LEFT JOIN geo_exclusions ex ON s.city_name_raw = ex.geo_label
WHERE relevance_score >= 2