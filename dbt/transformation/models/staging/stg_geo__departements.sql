SELECT
    TRIM(CAST(code AS STRING))   AS CODE_DEPARTEMENT,
    {{ clean_string('nom') }}    AS NOM,
    {{ clean_string('codeRegion') }} AS CODE_REGION
FROM {{ source('raw', 'geo_departements') }}
WHERE code IS NOT NULL
