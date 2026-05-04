{#
  Nettoie un libellé de commune :
  - Supprime les expressions entre parenthèses : "(75001)", "(XX)"
  - Supprime les tokens contenant des chiffres : "73655", "N18BZ"
  - Normalise les espaces
  Appliquer APRÈS clean_string.
  Usage : {{ clean_commune_tokens(clean_string('libelleCommuneEtablissement')) }}
#}
{% macro clean_commune_tokens(input) %}
    NULLIF(
        TRIM(REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE({{ input }}, r'\([^)]*\)', ''),
                r'\S*\d\S*', ''
            ),
            r'\s+', ' '
        )),
        ''
    )
{% endmacro %}
