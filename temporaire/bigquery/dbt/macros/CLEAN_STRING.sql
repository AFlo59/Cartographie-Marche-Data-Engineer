{% macro CLEAN_STRING(input) %}
{% set sq = "'" %}
{% set dq = '"' %}
{% set char_pattern = "[-" ~ dq ~ sq ~ "_*]" %}
    CASE
        WHEN {{ input }} IS NULL THEN NULL
        ELSE
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            UPPER(
                                NORMALIZE({{ input }}, NFD)
                            ),
                        r'\p{M}',
                        ''
                        ),
                    r"""{{ char_pattern }}""",
                    ' '
                    ),
                r'\s+',
                ' '
                )
            )
    END
{% endmacro %}
