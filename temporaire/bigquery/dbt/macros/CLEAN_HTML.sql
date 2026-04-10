{% macro CLEAN_HTML(input) %}
    {{ CLEAN_STRING("REGEXP_REPLACE(COALESCE(" ~ input ~ ", ''), r'<[^>]*>', ' ')") }}
{% endmacro %}
