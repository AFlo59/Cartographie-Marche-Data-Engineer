{% macro CLEAN_SIRET_VALID(input) %}
    CASE
        WHEN {{ input }} IS NULL THEN NULL
        WHEN LENGTH(REGEXP_REPLACE(CAST({{ input }} AS STRING), r'\D', '')) = 14
            THEN REGEXP_REPLACE(CAST({{ input }} AS STRING), r'\D', '')
        ELSE NULL
    END
{% endmacro %}
