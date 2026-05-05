SELECT DISTINCT
    TRIM(CAST(code AS STRING)) AS CODE_REGION,
    {{ clean_string('nom') }}  AS NOM
FROM {{ source('raw', 'geo_regions') }}
WHERE code IS NOT NULL
