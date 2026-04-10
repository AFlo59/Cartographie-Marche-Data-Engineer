{#
  Nettoie un nom de commune :
  - Supprime les expressions entre parenthèses : "(75001)", "(XX)"
  - Supprime les tokens contenant des chiffres  : "73655", "N18BZ", "8940"
  - Normalise les espaces
  Ne duplique pas les lignes (HONG KONG reste HONG KONG).
  Usage : {{ CLEAN_COMMUNE_TOKENS('libelleCommuneEtablissement') }}
#}
{% macro CLEAN_COMMUNE_TOKENS(input) %}
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
