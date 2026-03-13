with offres as (
    select *
    from {{ ref('stg_france_travail__offres') }}
),

sirene as (
    select *
    from {{ ref('stg_sirene__etablissements') }}
),

geo as (
    select *
    from {{ ref('stg_geo__communes') }}
),

enriched as (
    select
        o.offre_id,
        o.intitule_poste,
        o.type_contrat,
        o.date_publication,
        o.siret,
        s.siren,
        s.code_naf,
        coalesce(s.commune, g.commune) as commune,
        g.region
    from offres o
    left join sirene s
        on o.siret = s.siret
    left join geo g
        on o.code_postal = g.code_postal
)

select *
from enriched
