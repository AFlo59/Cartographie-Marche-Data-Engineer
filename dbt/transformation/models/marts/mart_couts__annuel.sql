{{ config(materialized='view') }}

SELECT
    -- Dimensions projet
    project.id                                              AS projet_id,

    -- Dimensions service & ressource
    service.description                                     AS service,
    sku.description                                         AS sku,
    resource.name                                           AS ressource_nom,
    resource.type                                           AS ressource_type,

    -- Dimensions localisation
    location.region                                         AS region,
    location.country                                        AS pays,

    -- Dimension type de coût (regular / tax / adjustment / rounding_error)
    cost_type                                               AS type_cout,

    -- Dimension temporelle
    EXTRACT(YEAR FROM usage_start_time)                     AS annee,

    -- Métriques
    ROUND(SUM(cost), 4)                                     AS cout_brut_eur,
    ROUND(SUM(
        COALESCE((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)
    ), 4)                                                   AS credits_eur,
    ROUND(
        SUM(cost) + SUM(
            COALESCE((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)
        ), 4
    )                                                       AS cout_net_eur

FROM {{ source('billing', 'gcp_billing_export_v1_01D8CD_F730D3_5EA02E') }}

WHERE project.id = '{{ env_var("GCP_PROJECT_ID") }}'

GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
