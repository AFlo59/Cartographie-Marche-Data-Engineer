{#
  Macro 1 — Appel UDF
  Usage : {{ PARSE_CONTRAT('ma_colonne') }}.type_contrat
           {{ PARSE_CONTRAT('ma_colonne') }}.duree_mois
           {{ PARSE_CONTRAT('ma_colonne') }}.type_duree
#}
{% macro PARSE_CONTRAT(input) %}
    `{{ target.project }}.{{ target.dataset }}.parse_contrat`({{ input }})
{% endmacro %}


{#
  Macro 2 — Création UDF persistante
  Usage : dbt run-operation create_parse_contrat_udf
#}
{% macro create_parse_contrat_udf() %}
    {% set sql %}
        CREATE OR REPLACE FUNCTION
            `{{ target.project }}.{{ target.dataset }}.parse_contrat`(input STRING)
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
                    WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:MOIS|MONTHS?)')          THEN 'MOIS'
                    WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:AN|ANS|YEAR|YEARS)')     THEN 'AN'
                    WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:SEMAINE|SEMAINES|WEEK|WEEKS)') THEN 'SEMAINE'
                    WHEN REGEXP_CONTAINS(UPPER(input), r'\d+\s*(?:JOUR|JOURS|DAY|DAYS)')   THEN 'JOUR'
                    ELSE NULL
                END
            )
        );
    {% endset %}

    {% do run_query(sql) %}
    {% do log("UDF parse_contrat créée dans " ~ target.project ~ "." ~ target.dataset, info=true) %}
{% endmacro %}
