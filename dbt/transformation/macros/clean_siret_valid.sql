{#
  Valide et normalise un SIRET : extrait les 14 chiffres, retourne NULL si longueur ≠ 14.
  Usage : {{ clean_siret_valid('entreprise_numeroSiret') }}
#}
{% macro clean_siret_valid(input) %}
    CASE
        WHEN {{ input }} IS NULL THEN NULL
        WHEN LENGTH(REGEXP_REPLACE(CAST({{ input }} AS STRING), r'\D', '')) = 14
            THEN REGEXP_REPLACE(CAST({{ input }} AS STRING), r'\D', '')
        ELSE NULL
    END
{% endmacro %}
