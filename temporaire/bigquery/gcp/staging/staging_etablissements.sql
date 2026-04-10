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
          THEN TIMESTAMP_MICROS(
            SAFE_CAST(SAFE_CAST(v AS BIGNUMERIC) / 1000 AS INT64)
          )
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

-- FIX: null guard + validation bornes Lambert 93 (France métropolitaine)
CREATE TEMP FUNCTION lambert93_to_latlon(x FLOAT64, y FLOAT64)
  RETURNS STRUCT<lat FLOAT64, lon FLOAT64>
  LANGUAGE js AS r"""

  if (x === null || y === null || x === undefined || y === undefined
      || isNaN(x) || isNaN(y)) {
    return {lat: null, lon: null};
  }
  if (x < 100000 || x > 1300000 || y < 6000000 || y > 7300000) {
    return {lat: null, lon: null};
  }

  var a  = 6378137.0;
  var e  = 0.0818191908426215;
  var e2 = e * e;

  var phi1    = 44.0 * Math.PI / 180;
  var phi2    = 49.0 * Math.PI / 180;
  var phi0    = 46.5 * Math.PI / 180;
  var lambda0 =  3.0 * Math.PI / 180;
  var X0      = 700000;
  var Y0      = 6600000;

  function m_func(phi) {
    return Math.cos(phi) / Math.sqrt(1 - e2 * Math.sin(phi) * Math.sin(phi));
  }
  function t_func(phi) {
    var sinPhi = Math.sin(phi);
    return Math.tan(Math.PI / 4 - phi / 2) /
           Math.pow((1 - e * sinPhi) / (1 + e * sinPhi), e / 2);
  }

  var m1 = m_func(phi1);
  var m2 = m_func(phi2);
  var t0 = t_func(phi0);
  var t1 = t_func(phi1);
  var t2 = t_func(phi2);

  var n  = (Math.log(m1) - Math.log(m2)) / (Math.log(t1) - Math.log(t2));
  var F  = m1 / (n * Math.pow(t1, n));
  var r0 = a * F * Math.pow(t0, n);

  var xi      = x - X0;
  var eta     = r0 - (y - Y0);
  var r_prime = Math.sqrt(xi * xi + eta * eta);
  var theta   = Math.atan2(xi, eta);
  var t_prime = Math.pow(r_prime / (a * F), 1.0 / n);

  var phi = Math.PI / 2 - 2 * Math.atan(t_prime);
  for (var i = 0; i < 10; i++) {
    var sinPhi = Math.sin(phi);
    phi = Math.PI / 2 - 2 * Math.atan(
      t_prime * Math.pow((1 - e * sinPhi) / (1 + e * sinPhi), e / 2)
    );
  }

  var lambda = theta / n + lambda0;
  return {
    lat: phi    * 180 / Math.PI,
    lon: lambda * 180 / Math.PI
  };
  """;

-- Supprime les tokens contenant des chiffres (ex: "73655", "N18BZ")
-- et les expressions entre parenthèses (ex: "(75001)").
-- Ne duplique pas les lignes : HONG KONG reste HONG KONG.
CREATE TEMP FUNCTION CLEAN_COMMUNE_TOKENS(input STRING)
RETURNS STRING
AS (
  NULLIF(
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(input, r'\([^)]*\)', ''),  -- supprime (...)
        r'\S*\d\S*', ''                            -- supprime tokens avec chiffres
      ),
      r'\s+', ' '                                  -- normalise les espaces
    )),
    ''
  )
);

-- ============================================================
-- MODEL
-- ============================================================

CREATE OR REPLACE TABLE staging.etablissements AS (

  WITH CLEANUP AS (
    SELECT
      CLEAN_STRING(enseigne1Etablissement)              AS NOM_1,
      CLEAN_STRING(enseigne2Etablissement)              AS NOM_2,
      CLEAN_STRING(enseigne3Etablissement)              AS NOM_3,
      CLEAN_STRING(denominationUsuelleEtablissement)    AS NOM_4,
      CLEAN_STRING(codePostalEtablissement)             AS CODE_POSTAL,
      CLEAN_COMMUNE_TOKENS(CLEAN_STRING(libelleCommuneEtablissement))         AS NOM_COMMUNE_1,
      CLEAN_COMMUNE_TOKENS(CLEAN_STRING(libelleCommuneEtrangerEtablissement)) AS NOM_COMMUNE_2,
      CLEAN_STRING(codeCommuneEtablissement)            AS CODE_INSEE,
      IF(
        SAFE_CAST(coordonneeLambertAbscisseEtablissement AS FLOAT64) IS NOT NULL
        AND SAFE_CAST(coordonneeLambertOrdonneeEtablissement AS FLOAT64) IS NOT NULL,
        lambert93_to_latlon(
          SAFE_CAST(coordonneeLambertAbscisseEtablissement AS FLOAT64),
          SAFE_CAST(coordonneeLambertOrdonneeEtablissement AS FLOAT64)
        ),
        NULL
      ) AS coords
    FROM `raw.sirene_etablissements`
  ),

  CLEANUP_FLAT AS (
    SELECT
      NOM_1, NOM_2, NOM_3, NOM_4,
      CODE_POSTAL, NOM_COMMUNE_1, NOM_COMMUNE_2, CODE_INSEE,
      coords.lat AS LATITUDE,
      coords.lon AS LONGITUDE,
      COALESCE(
        -- Depuis code_postal (5 chiffres)
        CASE
          WHEN REGEXP_CONTAINS(COALESCE(CODE_POSTAL, ''), r'^(97[1-6]|98[0-9])\d{2}$') THEN SUBSTR(CODE_POSTAL, 1, 3)
          WHEN REGEXP_CONTAINS(COALESCE(CODE_POSTAL, ''), r'^\d{5}$')                   THEN SUBSTR(CODE_POSTAL, 1, 2)
          ELSE NULL
        END,
        -- Depuis code commune INSEE (5 chiffres — permet de distinguer 2A/2B)
        CASE
          WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^2[AB]\d{3}$')               THEN SUBSTR(CODE_INSEE, 1, 2)
          WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^(97[1-6]|98[0-9])\d{2}$')  THEN SUBSTR(CODE_INSEE, 1, 3)
          WHEN REGEXP_CONTAINS(COALESCE(CODE_INSEE, ''), r'^\d{5}$')                    THEN SUBSTR(CODE_INSEE, 1, 2)
          ELSE NULL
        END
      ) AS DEPARTEMENT
    FROM CLEANUP
  ),

  UNION_DATA AS (
    SELECT NOM_1 AS NOM, NOM_COMMUNE_1 AS NOM_COMMUNE, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_1 IS NOT NULL AND NOM_1 != '' AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT NOM_2, NOM_COMMUNE_1, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_2 IS NOT NULL AND NOM_2 != '' AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT NOM_3, NOM_COMMUNE_1, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_3 IS NOT NULL AND NOM_3 != '' AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT NOM_4, NOM_COMMUNE_1, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_4 IS NOT NULL AND NOM_4 != '' AND NOM_COMMUNE_1 IS NOT NULL
    UNION ALL
    SELECT NOM_1, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_1 IS NOT NULL AND NOM_1 != '' AND NOM_COMMUNE_2 IS NOT NULL
    UNION ALL
    SELECT NOM_2, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_2 IS NOT NULL AND NOM_2 != '' AND NOM_COMMUNE_2 IS NOT NULL
    UNION ALL
    SELECT NOM_3, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_3 IS NOT NULL AND NOM_3 != '' AND NOM_COMMUNE_2 IS NOT NULL
    UNION ALL
    SELECT NOM_4, NOM_COMMUNE_2, CODE_INSEE, CODE_POSTAL, DEPARTEMENT, LATITUDE, LONGITUDE FROM CLEANUP_FLAT WHERE NOM_4 IS NOT NULL AND NOM_4 != '' AND NOM_COMMUNE_2 IS NOT NULL
  )

  SELECT DISTINCT
    NOM,
    NOM_COMMUNE,
    CODE_INSEE,
    CODE_POSTAL,
    DEPARTEMENT,
    LATITUDE,
    LONGITUDE
  FROM UNION_DATA

);
