{#
  Macro SQL — normalise le type de contrat vers une valeur canonique partagée entre toutes les sources.
  Retourne : CDI | CDD | INTERIM | ALTERNANCE | STAGE | FREELANCE | AUTRE

  Usage :
    {{ contract_type_normalized('code_contrat', 'intitule') }}

  Paramètres :
    code_expr    : expression SQL retournant le code brut (ex: CDI, CDD, MIS, typeContrat APEC…)
    libelle_expr : expression SQL retournant un libellé libre (titre offre, typeContratLibelle…)
#}
{% macro contract_type_normalized(code_expr, libelle_expr) %}
CASE
    -- Alternance / Apprentissage (titre prioritaire — souvent dans intitulé avant code)
    WHEN REGEXP_CONTAINS(UPPER(COALESCE({{ libelle_expr }}, '')), r'ALTERNANCE|APPRENTISSAGE|ALTERNANT')
        THEN 'ALTERNANCE'
    -- Stage
    WHEN REGEXP_CONTAINS(UPPER(COALESCE({{ libelle_expr }}, '')), r'\bSTAGE\b')
        THEN 'STAGE'
    -- Freelance / Indépendant / Portage (dans code ou libellé)
    WHEN REGEXP_CONTAINS(UPPER(COALESCE({{ libelle_expr }}, COALESCE({{ code_expr }}, ''))), r'FREELANCE|IND[EÉ]PENDANT|PORTAGE|LIB[EÉ]RAL|INDEPENDANT')
        THEN 'FREELANCE'
    -- Intérim / Mission (code FT = MIS, ou libellé explicite)
    WHEN UPPER(COALESCE({{ code_expr }}, '')) = 'MIS'
        OR REGEXP_CONTAINS(UPPER(COALESCE({{ libelle_expr }}, COALESCE({{ code_expr }}, ''))), r'\bINTERIM\b|\bMISSION INTERIM\b|TRAVAIL TEMPORAIRE')
        THEN 'INTERIM'
    -- CDI : code FT ou libellé générique
    WHEN UPPER(COALESCE({{ code_expr }}, '')) = 'CDI'
        OR REGEXP_CONTAINS(UPPER(COALESCE({{ libelle_expr }}, '')), r'\bCDI\b|DUREE INDETERMINEE|INDETERMINEE')
        THEN 'CDI'
    -- CDD et assimilés (SAI=saisonnier, DDI=insertion, DIN, CCE, CPI)
    WHEN UPPER(COALESCE({{ code_expr }}, '')) IN ('CDD', 'SAI', 'DDI', 'DIN', 'CCE', 'CPI')
        OR REGEXP_CONTAINS(UPPER(COALESCE({{ libelle_expr }}, COALESCE({{ code_expr }}, ''))), r'\bCDD\b|DUREE DETERMINEE|SAISONNIER|INSERTION')
        THEN 'CDD'
    -- Fallback
    ELSE 'AUTRE'
END
{% endmacro %}
