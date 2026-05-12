{{ config(materialized='view') }}

{#
  Failsafe : GCP cree la table billing export uniquement quand il y a des donnees.
  Si la table est absente, on retourne un schema vide plutot que de faire
  echouer le Cloud Run Job / Scheduler.
#}
{% if execute %}
  {% set relation_exists = adapter.get_relation(
      database=env_var('GCP_PROJECT_ID'),
      schema='billing_export',
      identifier='gcp_billing_export_v1_01D8CD_F730D3_5EA02E'
  ) is not none %}
{% else %}
  {% set relation_exists = true %}
{% endif %}

{% if relation_exists %}

SELECT
    -- Dimensions projet
    project.id                                              AS projet_id,

    -- Dimensions service
    service.description                                     AS service,
    sku.description                                         AS sku,

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

GROUP BY 1, 2, 3, 4, 5, 6, 7

{% else %}

-- Table billing non encore créée par GCP (export activé mais aucune donnée reçue).
-- Retourne un schéma vide pour ne pas bloquer le pipeline.
SELECT
    CAST(NULL AS STRING)  AS projet_id,
    CAST(NULL AS STRING)  AS service,
    CAST(NULL AS STRING)  AS sku,
    CAST(NULL AS STRING)  AS region,
    CAST(NULL AS STRING)  AS pays,
    CAST(NULL AS STRING)  AS type_cout,
    CAST(NULL AS INT64)   AS annee,
    CAST(NULL AS FLOAT64) AS cout_brut_eur,
    CAST(NULL AS FLOAT64) AS credits_eur,
    CAST(NULL AS FLOAT64) AS cout_net_eur
WHERE FALSE

{% endif %}
