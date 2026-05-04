{#
  UDF BigQuery — parse automatiquement un libellé de salaire.
  Retourne STRUCT<type, min_amount, max_amount, nb_mois, min_mensuel, max_mensuel, min_annuel, max_annuel>.
  Supporte les formats "Mensuel de X Euros à Y Euros sur N mois", "X k€ annuel", etc.

  Invocation :
    {{ parse_salaire_auto('salaire_libelle') }}.type
    {{ parse_salaire_auto('salaire_libelle') }}.min_mensuel

  Création UDF :
    • Automatique via on-run-start (parse_salaire_auto_udf_ddl())
    • Manuelle : dbt run-operation create_parse_salaire_auto_udf
#}

{% macro parse_salaire_auto(input) %}
    `{{ target.project }}.{{ target.dataset }}.parse_salaire_auto`({{ input }})
{% endmacro %}


{% macro parse_salaire_auto_udf_ddl() %}
    CREATE OR REPLACE FUNCTION
        `{{ target.project }}.{{ target.dataset }}.parse_salaire_auto`(input STRING)
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
                    SAFE_CAST(
                        REGEXP_EXTRACT(UPPER(TRIM(COALESCE(input, ''))), r'(\d+(?:[.,]\d+)?)\s*MOIS')
                    AS NUMERIC),
                    12
                ) AS INT64) AS nb_mois_val,
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
    ))
{% endmacro %}


{% macro create_parse_salaire_auto_udf() %}
    {% do run_query(parse_salaire_auto_udf_ddl()) %}
    {% do log("UDF parse_salaire_auto créée dans " ~ target.project ~ "." ~ target.dataset, info=true) %}
{% endmacro %}
