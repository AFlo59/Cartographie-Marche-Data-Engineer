{#
  Macro 1 — Appel UDF
  Usage : {{ PARSE_EVENT_TS('ma_colonne') }}
#}
{% macro PARSE_EVENT_TS(input) %}
    `{{ target.project }}.{{ target.dataset }}.parse_event_ts`(CAST({{ input }} AS STRING))
{% endmacro %}


{#
  Macro 2 — Création UDF persistante
  Usage : dbt run-operation create_parse_event_ts_udf
#}
{% macro create_parse_event_ts_udf() %}
    {% set sql %}
        CREATE OR REPLACE FUNCTION
            `{{ target.project }}.{{ target.dataset }}.parse_event_ts`(input STRING)
        RETURNS TIMESTAMP
        AS ((
            WITH s AS (
                SELECT TRIM(input) AS v
            )
            SELECT
                CASE
                    WHEN input IS NULL OR v = '' THEN NULL

                    -- Date ISO / string date
                    WHEN SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', v) IS NOT NULL
                        THEN SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', v)
                    WHEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%E*S', v) IS NOT NULL
                        THEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%E*S', v)
                    WHEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d', v) IS NOT NULL
                        THEN SAFE.PARSE_TIMESTAMP('%Y-%m-%d', v)

                    -- Numérique (epoch) : ns, us, ms, s
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
    {% endset %}

    {% do run_query(sql) %}
    {% do log("UDF parse_event_ts créée dans " ~ target.project ~ "." ~ target.dataset, info=true) %}
{% endmacro %}
