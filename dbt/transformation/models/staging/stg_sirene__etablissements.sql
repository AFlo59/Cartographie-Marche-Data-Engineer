{% set raw_schema = var('raw_schema', 'raw') %}

with source_data as (
    select
        cast(siret as string) as siret,
        cast(siren as string) as siren,
        cast(nomenclature_activite_principale as string) as code_naf,
        cast(libelle_commune as string) as commune,
        cast(code_postal as string) as code_postal
    from {{ target.database }}.{{ raw_schema }}.sirene_etablissements
),

cleaned as (
    select
        trim(regexp_replace(siret, r'[\t\r\n\s]+', '')) as siret,
        trim(regexp_replace(siren, r'[\t\r\n\s]+', '')) as siren,
        upper(trim(regexp_replace(regexp_replace(regexp_replace(code_naf, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))) as code_naf,
        upper(trim(regexp_replace(regexp_replace(regexp_replace(commune, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))) as commune,
        regexp_replace(normalize(upper(trim(regexp_replace(regexp_replace(regexp_replace(commune, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))), NFD), r'\pM', '') as commune_normalized,
        trim(regexp_replace(code_postal, r'[\t\r\n\s]+', '')) as code_postal
    from source_data
    where siret is not null and trim(regexp_replace(siret, r'[\t\r\n\s]+', '')) != ''
)

select *
from cleaned
