with source_data as (
    select *
    from {{ ref('int_offres_enrichies') }}
)

select
    offre_id,
    intitule_poste,
    type_contrat,
    date_publication,
    siret,
    siren,
    code_naf,
    commune,
    region
from source_data
