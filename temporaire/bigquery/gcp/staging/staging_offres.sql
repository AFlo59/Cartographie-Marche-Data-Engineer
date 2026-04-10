-- ============================================================
-- TEMP FUNCTIONS
-- ============================================================

CREATE TEMP FUNCTION CLEAN_STRING(input STRING)
RETURNS STRING
AS (
  CASE
    WHEN input IS NULL THEN NULL
    ELSE TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            UPPER(NORMALIZE(input, NFD)),
            r'\p{M}',
            ''
          ),
          r'[-"\'_*]',
          ' '
        ),
        r'\s+',
        ' '
      )
    )
  END
);

CREATE TEMP FUNCTION CLEAN_SIRET_VALID(input ANY TYPE)
RETURNS STRING
AS (
  CASE
    WHEN input IS NULL THEN NULL
    WHEN LENGTH(REGEXP_REPLACE(CAST(input AS STRING), r'\D', '')) = 14
      THEN REGEXP_REPLACE(CAST(input AS STRING), r'\D', '')
    ELSE NULL
  END
);

CREATE TEMP FUNCTION PARSE_EVENT_TS(input ANY TYPE)
RETURNS TIMESTAMP
AS (
  (
    WITH s AS (
      SELECT TRIM(CAST(input AS STRING)) AS v
    )
    SELECT
      CASE
        WHEN input IS NULL OR v = '' THEN NULL
        WHEN SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', v) IS NOT NULL
          THEN SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', v)
        WHEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%E*S', v) IS NOT NULL
          THEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%E*S', v)
        WHEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d', v) IS NOT NULL
          THEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d', v)
        WHEN REGEXP_CONTAINS(v, r'^\d+$') AND LENGTH(v) >= 19
          THEN TIMESTAMP_MICROS(SAFE_CAST(SAFE_CAST(v AS BIGNUMERIC) / 1000 AS INT64))
        WHEN REGEXP_CONTAINS(v, r'^\d+$') AND LENGTH(v) BETWEEN 16 AND 18
          THEN TIMESTAMP_MICROS(SAFE_CAST(v AS INT64))
        WHEN REGEXP_CONTAINS(v, r'^\d+$') AND LENGTH(v) BETWEEN 13 AND 15
          THEN TIMESTAMP_MILLIS(SAFE_CAST(v AS INT64))
        WHEN REGEXP_CONTAINS(v, r'^\d+$') AND LENGTH(v) BETWEEN 10 AND 12
          THEN TIMESTAMP_SECONDS(SAFE_CAST(v AS INT64))
        ELSE NULL
      END
    FROM s
  )
);

CREATE TEMP FUNCTION PARSE_CONTRAT(input STRING)
RETURNS STRUCT<type_contrat STRING, duree_mois NUMERIC, type_duree STRING>
AS (
  STRUCT<type_contrat STRING, duree_mois NUMERIC, type_duree STRING>(
    TRIM(
      CASE
        WHEN input IS NULL THEN NULL
        WHEN REGEXP_CONTAINS(input, r'\d') THEN REGEXP_EXTRACT(input, r'(\S+)\s*\d')
        ELSE REGEXP_EXTRACT(input, r'(\S+)')
      END
    ),
    CASE
      WHEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:MOIS|MONTHS?)') AS NUMERIC) IS NOT NULL
        THEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:MOIS|MONTHS?)') AS NUMERIC)
      WHEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:AN|ANS|YEAR|YEARS)') AS NUMERIC) IS NOT NULL
        THEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:AN|ANS|YEAR|YEARS)') AS NUMERIC) * 12
      WHEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:SEMAINE|SEMAINES|WEEK|WEEKS)') AS NUMERIC) IS NOT NULL
        THEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:SEMAINE|SEMAINES|WEEK|WEEKS)') AS NUMERIC) / 4
      WHEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:JOUR|JOURS|DAY|DAYS)') AS NUMERIC) IS NOT NULL
        THEN SAFE_CAST(REGEXP_EXTRACT(UPPER(input), r'(\d+)\s*(?:JOUR|JOURS|DAY|DAYS)') AS NUMERIC) / 30
      ELSE NULL
    END,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:MOIS|MONTHS?)')                THEN 'MOIS'
      WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:AN|ANS|YEAR|YEARS)')           THEN 'AN'
      WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:SEMAINE|SEMAINES|WEEK|WEEKS)') THEN 'SEMAINE'
      WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:JOUR|JOURS|DAY|DAYS)')         THEN 'JOUR'
      ELSE NULL
    END
  )
);

-- CLEAN_HTML référence CLEAN_STRING définie avant dans le même script
CREATE TEMP FUNCTION CLEAN_HTML(input STRING)
RETURNS STRING
AS (
  CLEAN_STRING(
    REGEXP_REPLACE(COALESCE(input, ''), r'<[^>]*>', ' ')
  )
);

CREATE TEMP FUNCTION PARSE_SALAIRE_AUTO(input STRING)
RETURNS STRUCT<
  type        STRING,
  min_amount  NUMERIC,
  max_amount  NUMERIC,
  nb_mois     INT64,
  min_mensuel NUMERIC,
  max_mensuel NUMERIC,
  min_annuel  NUMERIC,
  max_annuel  NUMERIC
>
AS (
  (
    WITH prep AS (
      SELECT
        UPPER(TRIM(COALESCE(input, ''))) AS s,
        -- nb_mois : extrait le nombre AVANT le mot MOIS (ex: "sur 14.0 mois" → 14)
        -- Converti en INT64 ; défaut 12 si absent
        CAST(COALESCE(
          SAFE_CAST(
            REGEXP_EXTRACT(UPPER(TRIM(COALESCE(input, ''))), r'(\d+(?:[.,]\d+)?)\s*MOIS')
          AS NUMERIC),
          12
        ) AS INT64) AS nb_mois_val,
        -- Montants salariaux : on retire d'abord le token "X.X MOIS" pour ne pas
        -- confondre le nombre de mois avec un montant (ex: 14.0 dans "sur 14.0 mois")
        REGEXP_EXTRACT_ALL(
          REGEXP_REPLACE(
            UPPER(TRIM(COALESCE(input, ''))),
            r'\d+(?:[.,]\d+)?\s*MOIS',
            ''
          ),
          r'\d+(?:[.,]\d+)?'
        ) AS nums
    )
    SELECT STRUCT<
      type        STRING,
      min_amount  NUMERIC,
      max_amount  NUMERIC,
      nb_mois     INT64,
      min_mensuel NUMERIC,
      max_mensuel NUMERIC,
      min_annuel  NUMERIC,
      max_annuel  NUMERIC
    >(
      CASE
        WHEN s LIKE '%MENSUEL%' THEN 'MENSUEL'
        WHEN s LIKE '%ANNUEL%'  THEN 'ANNUEL'
        ELSE NULL
      END,
      IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC), NULL),
      IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC), NULL),
      nb_mois_val,
      CASE
        WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC), NULL)
        WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) / nb_mois_val, NULL)
        ELSE NULL
      END,
      CASE
        WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC), NULL)
        WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) / nb_mois_val, NULL)
        ELSE NULL
      END,
      CASE
        WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC), NULL)
        WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) * nb_mois_val, NULL)
        ELSE NULL
      END,
      CASE
        WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC), NULL)
        WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) * nb_mois_val, NULL)
        ELSE NULL
      END
    )
    FROM prep
  )
);

-- ============================================================
-- MODEL
-- ============================================================

CREATE OR REPLACE TABLE staging.offres AS

WITH cleanup AS (
  SELECT
    id,

    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          CLEAN_STRING(intitule),
          r'\s*\(?\b[HF]/[FH]\b\)?',
          ''
        ),
        r'\s*[/\\]\s*\S+',
        ''
      )
    ) AS intitule,

    CLEAN_HTML(description)      AS description,
    PARSE_EVENT_TS(dateCreation) AS date_creation,

    CASE
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
        THEN CAST(lieuTravail_codePostal AS STRING)
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{4}$')
        THEN CONCAT('0', CAST(lieuTravail_codePostal AS STRING))
      ELSE CLEAN_STRING(CAST(lieuTravail_codePostal AS STRING))
    END AS code_postal,

    CLEAN_STRING(CAST(lieuTravail_commune AS STRING)) AS code_insee,

    CASE
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^(97[1-6]|98[0-9])\d{2}$')
        THEN SUBSTR(CAST(lieuTravail_codePostal AS STRING), 1, 3)
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
        THEN SUBSTR(CAST(lieuTravail_codePostal AS STRING), 1, 2)
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^(2A|2B)\b')
        THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(2A|2B)\b')
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^(97[1-6]|98[0-9])\b')
        THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(97[1-6]|98[0-9])\b')
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^\d{2}\b')
        THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(\d{2})\b')
      ELSE NULL
    END AS departement,

    REGEXP_EXTRACT(
      CLEAN_STRING(CAST(lieuTravail_libelle AS STRING)),
      r'^(?:\d{2,3}|2A|2B)\s+(.+)$'
    ) AS nom_commune,

    CLEAN_STRING(CAST(entreprise_nom AS STRING))                        AS nom,
    CLEAN_SIRET_VALID(entreprise_numeroSiret)                           AS siret,
    PARSE_SALAIRE_AUTO(CAST(salaire_libelle AS STRING))                 AS salaire,
    CLEAN_STRING(CAST(salaire_complement1 AS STRING))                   AS bonus,
    CLEAN_STRING(CAST(typeContrat AS STRING))                           AS code_contrat,
    PARSE_CONTRAT(CLEAN_STRING(CAST(typeContratLibelle AS STRING)))     AS contrat,
    CLEAN_STRING(CAST(experienceExige AS STRING))                       AS experience,
    CLEAN_STRING(CAST(qualificationCode AS STRING))                     AS qualification,

    COALESCE(
      SAFE_CAST(dt AS DATE),
      SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
      SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
    ) AS date_insertion

  FROM `raw.france_travail_offres`
),

dedup AS (
  SELECT *
  FROM cleanup
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id
    ORDER BY date_creation DESC NULLS LAST, date_insertion DESC NULLS LAST
  ) = 1
)

SELECT * FROM dedup;