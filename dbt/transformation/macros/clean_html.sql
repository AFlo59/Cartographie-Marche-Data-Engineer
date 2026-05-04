{#
  Supprime les balises HTML puis applique clean_string.
  Retourne NULL si le résultat est une chaîne vide ou NULL.
  Usage : {{ clean_html('description') }}
#}
{% macro clean_html(input) %}
    NULLIF(
        {{ clean_string("REGEXP_REPLACE(COALESCE(" ~ input ~ ", ''), r'<[^>]*>', ' ')") }},
        ''
    )
{% endmacro %}
