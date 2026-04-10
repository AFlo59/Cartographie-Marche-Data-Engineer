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

-- ============================================================
-- MODEL
-- ============================================================

CREATE OR REPLACE TABLE staging.communes AS (

  WITH cleanup AS (
    SELECT
      CLEAN_STRING(code) AS CODE_INSEE,

      TRIM(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            CLEAN_STRING(nom),
            r'\s*\(?\b[HF]/[FH]\b\)?',
            ''
          ),
          r'\s*[/\\]\s*\S+',
          ''
        )
      ) AS NOM,

      CLEAN_STRING(codeRegion)      AS REGION_FK,
      CLEAN_STRING(codeDepartement) AS DEPARTEMENT,

      codesPostaux,

      CAST(ROUND(population) AS INT64) AS POPULATION,
      SAFE_CAST(latitude  AS FLOAT64)  AS LATITUDE,
      SAFE_CAST(longitude AS FLOAT64)  AS LONGITUDE

    FROM `raw.geo_communes`
  ),

  exploded AS (
    SELECT
      CODE_INSEE,
      NOM,
      REGION_FK,
      DEPARTEMENT,
      CLEAN_STRING(TRIM(cp)) AS CODE_POSTAL,
      POPULATION,
      LATITUDE,
      LONGITUDE
    FROM cleanup,
    UNNEST(SPLIT(codesPostaux, ',')) AS cp
  ),

  filtered AS (
    SELECT *
    FROM exploded
    WHERE CODE_POSTAL IS NOT NULL
      AND CODE_POSTAL != ''
  ),

  dedup AS (
    SELECT *
    FROM filtered
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY NOM, CODE_POSTAL
      ORDER BY CODE_INSEE
    ) = 1
  )

  SELECT * FROM dedup

);
