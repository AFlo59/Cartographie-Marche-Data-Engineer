-- =============================================================================
-- 00_udfs.sql — Fonctions BigQuery du pipeline Data Engineering
-- Projet : cartographie-data-engineer | Dataset : staging
--
-- Executer en premier avant tout autre script.
-- Compatible BigQuery console (multi-statement) et bq query (--nouse_legacy_sql).
-- Les UDFs sont persistantes : elles survivent aux redemarrages et sont reutilisables.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- clean_string : normalisation texte standard
-- UPPER + suppression accents (NFD) + non-alphanum -> espace + collapse espaces
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.clean_string`(input STRING)
RETURNS STRING
AS (
    CASE
        WHEN input IS NULL THEN NULL
        ELSE TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        UPPER(NORMALIZE(input, NFD)),
                        r'\p{M}', ''
                    ),
                    r'[^\p{L}\p{N}]', ' '
                ),
                r'  +', ' '
            )
        )
    END
);

-- ---------------------------------------------------------------------------
-- clean_html : suppression balises HTML puis clean_string
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.clean_html`(input STRING)
RETURNS STRING
AS (
    NULLIF(
        `cartographie-data-engineer.staging.clean_string`(
            REGEXP_REPLACE(COALESCE(input, ''), r'<[^>]*>', ' ')
        ),
        ''
    )
);

-- ---------------------------------------------------------------------------
-- clean_siret_valid : valide et normalise un SIRET (14 chiffres exactement)
-- Retourne NULL si longueur != 14 apres extraction des chiffres
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.clean_siret_valid`(input STRING)
RETURNS STRING
AS (
    CASE
        WHEN input IS NULL THEN NULL
        WHEN LENGTH(REGEXP_REPLACE(CAST(input AS STRING), r'\D', '')) = 14
            THEN REGEXP_REPLACE(CAST(input AS STRING), r'\D', '')
        ELSE NULL
    END
);

-- ---------------------------------------------------------------------------
-- clean_commune_tokens : supprime codes postaux entre parentheses et tokens chiffres
-- Appliquer APRES clean_string
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.clean_commune_tokens`(input STRING)
RETURNS STRING
AS (
    NULLIF(
        TRIM(REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(COALESCE(input, ''), r'\([^)]*\)', ''),
                r'\S*\d\S*', ''
            ),
            r'\s+', ' '
        )),
        ''
    )
);

-- ---------------------------------------------------------------------------
-- normalize_company_name : normalise un nom d entreprise pour jointure SIRENE
-- Applique clean_string et retourne NULL si vide
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.normalize_company_name`(input STRING)
RETURNS STRING
AS (
    NULLIF(TRIM(`cartographie-data-engineer.staging.clean_string`(input)), '')
);

-- ---------------------------------------------------------------------------
-- contract_type_normalized : normalise le type de contrat vers valeur canonique
-- Retourne : CDI | CDD | INTERIM | ALTERNANCE | STAGE | FREELANCE | AUTRE
-- code   : code brut (ex: CDI, CDD, MIS, typeContrat APEC...)
-- libelle : libelle libre (titre offre, typeContratLibelle...)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.contract_type_normalized`(
    code    STRING,
    libelle STRING
)
RETURNS STRING
AS (
    CASE
        WHEN REGEXP_CONTAINS(UPPER(COALESCE(libelle, '')), r'ALTERNANCE|APPRENTISSAGE|ALTERNANT')
            THEN 'ALTERNANCE'
        WHEN REGEXP_CONTAINS(UPPER(COALESCE(libelle, '')), r'\bSTAGE\b')
            THEN 'STAGE'
        WHEN REGEXP_CONTAINS(
            UPPER(COALESCE(libelle, COALESCE(code, ''))),
            r'FREELANCE|IND[EE]PENDANT|PORTAGE|LIB[EE]RAL|INDEPENDANT'
        )
            THEN 'FREELANCE'
        WHEN UPPER(COALESCE(code, '')) = 'MIS'
            OR REGEXP_CONTAINS(
                UPPER(COALESCE(libelle, COALESCE(code, ''))),
                r'\bINTERIM\b|\bMISSION INTERIM\b|TRAVAIL TEMPORAIRE'
            )
            THEN 'INTERIM'
        WHEN UPPER(COALESCE(code, '')) = 'CDI'
            OR REGEXP_CONTAINS(
                UPPER(COALESCE(libelle, '')),
                r'\bCDI\b|DUREE INDETERMINEE|INDETERMINEE'
            )
            THEN 'CDI'
        WHEN UPPER(COALESCE(code, '')) IN ('CDD', 'SAI', 'DDI', 'DIN', 'CCE', 'CPI')
            OR REGEXP_CONTAINS(
                UPPER(COALESCE(libelle, COALESCE(code, ''))),
                r'\bCDD\b|DUREE DETERMINEE|SAISONNIER|INSERTION'
            )
            THEN 'CDD'
        ELSE 'AUTRE'
    END
);

-- ---------------------------------------------------------------------------
-- relevance_score_data_eng : score de pertinence Data Engineering (INT64)
-- +15 titre explicite Data Engineer
-- +3  "data" dans le titre sans "engineer"
-- +4  stack DE dans la description (Spark, Kafka, Airflow, dbt...)
-- +2  langages (Python, SQL, Scala...)
-- +2  cloud (GCP, AWS, Azure...)
-- -20 metiers sans rapport (technicien, comptable, commercial...)
-- -5  management / product sans data dans le titre
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.relevance_score_data_eng`(
    intitule    STRING,
    description STRING
)
RETURNS INT64
AS ((
    CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE(intitule, '')),
        r'data engineer|data eng\b|ing[eé]nieur.{0,15}donn[eé]es?|ing[eé]nieur data|data pipeline|data platform'
    ) THEN 15 ELSE 0 END

    + CASE
        WHEN NOT REGEXP_CONTAINS(LOWER(COALESCE(intitule, '')),
            r'data engineer|ing[eé]nieur data|data pipeline|data platform')
          AND REGEXP_CONTAINS(LOWER(COALESCE(intitule, '')),
            r'\bdata\b|\bdonn[eé]es?\b|\banalytics?\b')
        THEN 3
        ELSE 0
    END

    + CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE(description, '')),
        r'\b(spark|pyspark|kafka|airflow|dbt|bigquery|snowflake|databricks|hadoop|hive|flink|redshift|synapse|dataflow|apache beam|luigi|prefect|dagster|dask|talend|informatica|nifi|fivetran|stitch|glue|athena|trino|presto)\b'
    ) THEN 4 ELSE 0 END

    + CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE(description, '')),
        r'\b(python|scala|sql|spark sql|hive ?ql|t-sql|pl.sql|pyspark|java)\b'
    ) THEN 2 ELSE 0 END

    + CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE(description, '')),
        r'\b(gcp|google cloud|aws|azure|cloud storage|amazon s3|\bgcs\b|blob storage|cloud run|cloud functions?|lambda|emr|dataproc)\b'
    ) THEN 2 ELSE 0 END

    - CASE WHEN REGEXP_CONTAINS(
        LOWER(COALESCE(intitule, '')),
        r'technicien|technicienne|maintenance|r[eé]seaux?|cybers[eé]curit[eé]|helpdesk|support (technique|informatique)|comptable|commercial(e)?|vendeur|vendeuse|gestionnaire de stock|logistique|supply chain|conducteur|chauffeur|infirmier|aide.soignant|m[eé]canicien|[eé]lectricien|plombier|menuisier|serveur|serveuse|agent de s[eé]curit[eé]'
    ) THEN 20 ELSE 0 END

    - CASE
        WHEN REGEXP_CONTAINS(
            LOWER(COALESCE(intitule, '')),
            r'scrum master|product owner|chef de projet|directeur|responsable|manager'
        )
        AND NOT REGEXP_CONTAINS(
            LOWER(COALESCE(intitule, '')),
            r'\bdata\b|\bdonn[eé]es?\b'
        )
        THEN 5
        ELSE 0
    END
));

-- ---------------------------------------------------------------------------
-- matching_confidence_data_eng : label de confiance depuis le score
-- Retourne : HIGH | MEDIUM | LOW | NOT_RELEVANT
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.matching_confidence_data_eng`(score INT64)
RETURNS STRING
AS (
    CASE
        WHEN score >= 15 THEN 'HIGH'
        WHEN score >= 5  THEN 'MEDIUM'
        WHEN score >  0  THEN 'LOW'
        ELSE 'NOT_RELEVANT'
    END
);

-- ---------------------------------------------------------------------------
-- parse_event_ts : parse un timestamp flexible (ISO 8601, epoch ns/us/ms/s)
-- Retourne NULL pour toute entree non parseable
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.parse_event_ts`(input STRING)
RETURNS TIMESTAMP
AS ((
    WITH s AS (SELECT TRIM(input) AS v)
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
));

-- ---------------------------------------------------------------------------
-- parse_contrat : parse le libelle de type de contrat
-- Retourne STRUCT<type_contrat STRING, duree_mois NUMERIC, type_duree STRING>
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.parse_contrat`(input STRING)
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

-- ---------------------------------------------------------------------------
-- parse_salaire_auto : parse automatiquement un libelle de salaire
-- Supporte : "Mensuel de X Euros a Y Euros sur N mois", "X k euros annuel"
-- Retourne STRUCT avec type, min/max amount, periodes, min/max mensuel, min/max annuel
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.parse_salaire_auto`(input STRING)
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
AS ((
    WITH prep AS (
        SELECT
            UPPER(TRIM(COALESCE(input, ''))) AS s,
            CAST(COALESCE(
                NULLIF(SAFE_CAST(
                    REGEXP_EXTRACT(UPPER(TRIM(COALESCE(input, ''))), r'(\d+(?:[.,]\d+)?)\s*MOIS')
                AS NUMERIC), 0),
                12
            ) AS INT64) AS nb_mois_val,
            REGEXP_EXTRACT_ALL(
                REGEXP_REPLACE(
                    UPPER(TRIM(COALESCE(input, ''))),
                    r'\d+(?:[.,]\d+)?\s*MOIS', ''
                ),
                r'\d+(?:[.,]\d+)?'
            ) AS nums,
            IF(REGEXP_CONTAINS(UPPER(TRIM(COALESCE(input, ''))), r'K\s*[€E]|KEUR'), 1000, 1) AS multiplier
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
        IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) * multiplier, NULL),
        IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) * multiplier, NULL),
        nb_mois_val,
        CASE
            WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) * multiplier, NULL)
            WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) * multiplier / nb_mois_val, NULL)
            ELSE NULL
        END,
        CASE
            WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) * multiplier, NULL)
            WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) * multiplier / nb_mois_val, NULL)
            ELSE NULL
        END,
        CASE
            WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) * multiplier, NULL)
            WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 1, SAFE_CAST(REPLACE(nums[OFFSET(0)], ',', '.') AS NUMERIC) * multiplier * nb_mois_val, NULL)
            ELSE NULL
        END,
        CASE
            WHEN s LIKE '%ANNUEL%'  THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) * multiplier, NULL)
            WHEN s LIKE '%MENSUEL%' THEN IF(ARRAY_LENGTH(nums) >= 2, SAFE_CAST(REPLACE(nums[OFFSET(1)], ',', '.') AS NUMERIC) * multiplier * nb_mois_val, NULL)
            ELSE NULL
        END
    )
    FROM prep
));

-- ---------------------------------------------------------------------------
-- lambert93_to_latlon : conversion Lambert-93 (EPSG:2154) -> WGS84 (EPSG:4326)
-- Ellipsoide GRS80. Precision < 1 mm sur la France metropolitaine.
-- Retourne STRUCT<lat FLOAT64, lon FLOAT64>, NULL hors bornes metropolitaines
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `cartographie-data-engineer.staging.lambert93_to_latlon`(x FLOAT64, y FLOAT64)
RETURNS STRUCT<lat FLOAT64, lon FLOAT64>
LANGUAGE js AS r"""
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
  var m1 = m_func(phi1), m2 = m_func(phi2);
  var t0 = t_func(phi0), t1 = t_func(phi1), t2 = t_func(phi2);
  var n  = (Math.log(m1) - Math.log(m2)) / (Math.log(t1) - Math.log(t2));
  var F  = m1 / (n * Math.pow(t1, n));
  var r0 = a * F * Math.pow(t0, n);
  if (x === null || y === null) return null;
  if (x < 100000 || x > 1300000 || y < 6000000 || y > 7300000) return null;
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
  return { lat: phi * 180 / Math.PI, lon: lambda * 180 / Math.PI };
""";
