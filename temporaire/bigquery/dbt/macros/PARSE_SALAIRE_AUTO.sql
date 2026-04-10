{#
  Macro 1 — Appel UDF
  Usage : {{ PARSE_SALAIRE_AUTO('ma_colonne') }}.type
           {{ PARSE_SALAIRE_AUTO('ma_colonne') }}.min_mensuel
           {{ PARSE_SALAIRE_AUTO('ma_colonne') }}.max_annuel  ...
#}
{% macro PARSE_SALAIRE_AUTO(input) %}
    `{{ target.project }}.{{ target.dataset }}.parse_salaire_auto`({{ input }})
{% endmacro %}


{#
  Macro 2 — Création UDF persistante
  Usage : dbt run-operation create_parse_salaire_auto_udf
#}
{% macro create_parse_salaire_auto_udf() %}
    {% set sql %}
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
                    -- nb_mois : extrait le nombre avant MOIS (gère "sur 14.0 mois", "sur 12 mois"…)
                    CAST(COALESCE(
                        SAFE_CAST(
                            REGEXP_EXTRACT(UPPER(TRIM(COALESCE(input, ''))), r'(\d+(?:[.,]\d+)?)\s*MOIS')
                        AS NUMERIC),
                        12
                    ) AS INT64) AS nb_mois_val,
                    -- Montants salariaux : on retire "X.X MOIS" avant d'extraire les nombres
                    -- pour ne pas confondre le nombre de mois avec un montant
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
        ));
    {% endset %}

    {% do run_query(sql) %}
    {% do log("UDF parse_salaire_auto créée dans " ~ target.project ~ "." ~ target.dataset, info=true) %}
{% endmacro %}
