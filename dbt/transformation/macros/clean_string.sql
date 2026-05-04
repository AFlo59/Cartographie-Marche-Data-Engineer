{#
  Nettoyage standard pour une valeur texte.
  Ordre des transformations :
    1. UPPER
    2. Suppression des accents (NFD + \p{M})
    3. Remplacement de tout caractere non-lettre / non-chiffre par un espace
    4. Collapse des espaces multiples vers 1 espace
    5. TRIM des espaces en tete et queue
  Retourne NULL pour toute entree NULL.
#}
{% macro clean_string(input) %}
CASE
    WHEN {{ input }} IS NULL THEN NULL
    ELSE
        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        UPPER(NORMALIZE({{ input }}, NFD)),
                        r'\p{M}',
                        ''
                    ),
                    r'[^\p{L}\p{N}]',
                    ' '
                ),
                r'  +',
                ' '
            )
        )
END
{% endmacro %}
