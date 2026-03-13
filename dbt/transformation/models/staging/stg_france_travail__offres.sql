{% set raw_schema = var('raw_schema', 'raw') %}

with source_data as (
    select
        cast(id_offre as string) as offre_id,
        cast(intitule as string) as intitule_poste,
        cast(entreprise_siret as string) as siret,
        cast(lieu_travail_code_postal as string) as code_postal,
        cast(date_creation as timestamp) as date_creation,
        cast(type_contrat as string) as type_contrat
    from {{ target.database }}.{{ raw_schema }}.france_travail_offres
),

cleaned as (
    select
        trim(regexp_replace(offre_id, r'[\t\r\n\s]+', '')) as offre_id,
        upper(trim(regexp_replace(regexp_replace(regexp_replace(intitule_poste, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))) as intitule_poste,
        regexp_replace(normalize(upper(trim(regexp_replace(regexp_replace(regexp_replace(intitule_poste, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))), NFD), r'\pM', '') as intitule_poste_normalized,
        trim(regexp_replace(siret, r'[\t\r\n\s]+', '')) as siret,
        trim(regexp_replace(code_postal, r'[\t\r\n\s]+', '')) as code_postal,
        date(date_creation) as date_publication,
        upper(trim(regexp_replace(regexp_replace(regexp_replace(type_contrat, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))) as type_contrat,
        regexp_replace(normalize(upper(trim(regexp_replace(regexp_replace(regexp_replace(type_contrat, r'[\t\r\n]+', ' '), r'[-''’]+', ' '), r'\s+', ' '))), NFD), r'\pM', '') as type_contrat_normalized
    from source_data
    where offre_id is not null and trim(regexp_replace(offre_id, r'[\t\r\n\s]+', '')) != ''
)

select *
from cleaned
