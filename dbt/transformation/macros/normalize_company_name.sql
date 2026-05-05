{#
  Macro SQL — normalise un nom d'entreprise pour jointure SIRENE.
  Applique clean_string (uppercase + NFD + accent removal + collapse), puis supprime
  les caractères séparateurs (tiret, guillemet, underscore, point) avant un TRIM final.

  Retourne NULL si l'entrée est vide ou nulle.

  Usage : {{ normalize_company_name('nom') }}

  Important : utilise clean_string() — doit être invoqué dans un contexte où
  la macro clean_string est disponible (même projet dbt).
#}
{% macro normalize_company_name(name_expr) %}
CASE
    WHEN {{ clean_string(name_expr) }} IS NULL
      OR TRIM({{ clean_string(name_expr) }}) = ''
        THEN NULL
    ELSE TRIM(REGEXP_REPLACE(
        REGEXP_REPLACE({{ clean_string(name_expr) }}, r'[-\'"_\.]', ' '),
        r'\s+', ' '
    ))
END
{% endmacro %}
