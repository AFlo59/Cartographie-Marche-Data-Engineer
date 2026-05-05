WITH raw_apec AS (
  SELECT * FROM `cartographie-data-engineer.raw.apec_offres`
  WHERE dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
),

processed_apec AS (
  SELECT 
    apec_id as source_id,
    'apec' as source_name,
    
    -- Nettoyage Title (Emoji + Whitespace)
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(job_title, r'[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]', ''), 
      r'\s{2,}', ' '
    )) as title,

    -- Nettoyage Description (Emoji + Newlines + Whitespace)
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(REPLACE(job_description_preview, r'\u0027', "'"), r'[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]', ''),
        r'[\t\n\r]+', ' '
      ),
      r'\s{2,}', ' '
    )) as description,

    company_name,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%z', published_at_text) as published_at,
    DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%z', published_at_text)) as published_date,
    salary_text as salary_raw,
    location_text as location_raw,
    departement as department_code,
    UPPER(TRIM(REGEXP_REPLACE(NORMALIZE(commune, NFD), r"[\pM]|[0-9]|ARRONDISSEMENT|ER\b|E\b|EME\b", ""))) as city_name_norm,
    CAST(latitude AS FLOAT64) as latitude,
    CAST(longitude AS FLOAT64) as longitude,

    -- LOGIQUE CONTRAT HARMONISÉE (Inclusion Freelance)
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(job_title), r'freelance|indépendant|independant') THEN 'Freelance'
      WHEN REGEXP_CONTAINS(LOWER(contract_type), r'(apprentissage|alternance|pro)') THEN 'Alternance' 
      WHEN contract_type = 'Stage' THEN 'Stage' 
      WHEN contract_type = 'CDI' THEN 'CDI' 
      WHEN REGEXP_CONTAINS(LOWER(contract_type), r'libéral|indépendant') THEN 'Freelance'
      ELSE 'CDD/Intérim' 
    END as contract_type,

    (
      CASE WHEN REGEXP_CONTAINS(LOWER(job_title), r'(consultant.*data|data.*analyst|analyste.*data|data.*steward|data.*architect|architecte.*data|data.*qualiticien|data.*engineer|ingénieur.*data|data.*analytics|lead.*data|data.*lead|tech.*lead.*data|data.*officer|chef.*projet.*data|developpeur.*data)') THEN 15 ELSE 0 END -
      CASE WHEN REGEXP_CONTAINS(LOWER(job_title), r'(supply chain|logistique|automobile|maintenance|achat|purchasing|validation|rh|recrutement)') THEN 20 ELSE 0 END
    ) as relevance_score,
    
    UPPER(REGEXP_REPLACE(NORMALIZE(company_name, NFD), r"[^\w]", "")) as company_key
  FROM raw_apec
  QUALIFY ROW_NUMBER() OVER(PARTITION BY apec_id ORDER BY dt DESC) = 1
),

salary_parsing AS (
  SELECT *,
    -- Sur l'APEC, le salaire est souvent "45 - 55 k€", on extrait le nombre et on multiplie par 1000
    SAFE_CAST(REGEXP_EXTRACT(salary_raw, r'([0-9]+)') AS FLOAT64) * 1000 as raw_sal_1,
    SAFE_CAST(REGEXP_EXTRACT(salary_raw, r'- ([0-9]+)') AS FLOAT64) * 1000 as raw_sal_2
  FROM processed_apec
)

SELECT 
  * EXCEPT(relevance_score, raw_sal_1, raw_sal_2),
  
  -- Sécurité Salary Multiplier pour Freelance (si jamais le salaire est un TJM < 2000)
  CAST(CASE 
    WHEN contract_type = 'Freelance' AND raw_sal_1 < 2000 THEN raw_sal_1 / 1000 
    ELSE raw_sal_1 
  END AS INT64) as salary_min,
  
  CAST(CASE 
    WHEN contract_type = 'Freelance' AND COALESCE(raw_sal_2, raw_sal_1) < 2000 THEN COALESCE(raw_sal_2, raw_sal_1) / 1000 
    ELSE COALESCE(raw_sal_2, raw_sal_1) 
  END AS INT64) as salary_max,

  CASE WHEN relevance_score >= 15 THEN 'High' ELSE 'Low' END as matching_confidence
FROM salary_parsing 
WHERE relevance_score > 0