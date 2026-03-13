{% set raw_schema = var('raw_schema', 'raw') %}

with source_data as (
    select
        cast(code_postal as string) as code_postal,
        cast(code_insee as string) as code_insee,
        cast(nom_commune as string) as commune,
        cast(region as string) as region
    from {{ target.database }}.{{ raw_schema }}.geo_communes
),

cleaned as (
    select
        trim(regexp_replace(code_postal, r'[\t\r\n\s]+', '')) as code_postal,
        trim(regexp_replace(code_insee, r'[\t\r\n\s]+', '')) as code_insee,
        upper(trim(regexp_replace(regexp_replace(regexp_replace(commune, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))) as commune,
        regexp_replace(normalize(upper(trim(regexp_replace(regexp_replace(regexp_replace(commune, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))), NFD), r'\pM', '') as commune_normalized,
        upper(trim(regexp_replace(regexp_replace(regexp_replace(region, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))) as region,
        regexp_replace(normalize(upper(trim(regexp_replace(regexp_replace(regexp_replace(region, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))), NFD), r'\pM', '') as region_normalized
    from source_data
    where code_postal is not null and trim(regexp_replace(code_postal, r'[\t\r\n\s]+', '')) != ''
)

select *
from cleaned
