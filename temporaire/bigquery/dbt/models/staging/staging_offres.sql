WITH cleanup AS (
  SELECT
    id,

    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          {{ CLEAN_STRING('intitule') }},
          r'\s*\(?\b[HF]/[FH]\b\)?',
          ''
        ),
        r'\s*[/\\]\s*\S+',
        ''
      )
    ) AS intitule,

    {{ CLEAN_HTML('description') }}      AS description,
    {{ PARSE_EVENT_TS('dateCreation') }} AS date_creation,

    CASE
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
        THEN CAST(lieuTravail_codePostal AS STRING)
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{4}$')
        THEN CONCAT('0', CAST(lieuTravail_codePostal AS STRING))
      ELSE {{ CLEAN_STRING('CAST(lieuTravail_codePostal AS STRING)') }}
    END AS code_postal,

    {{ CLEAN_STRING('CAST(lieuTravail_commune AS STRING)') }} AS code_insee,

    CASE
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^(97[1-6]|98[0-9])\d{2}$')
        THEN SUBSTR(CAST(lieuTravail_codePostal AS STRING), 1, 3)
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$')
        THEN SUBSTR(CAST(lieuTravail_codePostal AS STRING), 1, 2)
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^(2A|2B)\b')
        THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(2A|2B)\b')
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^(97[1-6]|98[0-9])\b')
        THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(97[1-6]|98[0-9])\b')
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(CAST(lieuTravail_libelle AS STRING), '')), r'^\d{2}\b')
        THEN REGEXP_EXTRACT(UPPER(CAST(lieuTravail_libelle AS STRING)), r'^(\d{2})\b')
      ELSE NULL
    END AS departement,

    REGEXP_EXTRACT(
      {{ CLEAN_STRING('CAST(lieuTravail_libelle AS STRING)') }},
      r'^(?:\d{2,3}|2A|2B)\s+(.+)$'
    ) AS nom_commune,

    {{ CLEAN_STRING('CAST(entreprise_nom AS STRING)') }}                                    AS nom,
    {{ CLEAN_SIRET_VALID('entreprise_numeroSiret') }}                                       AS siret,
    {{ PARSE_SALAIRE_AUTO('CAST(salaire_libelle AS STRING)') }}                             AS salaire,
    {{ CLEAN_STRING('CAST(salaire_complement1 AS STRING)') }}                               AS bonus,
    {{ CLEAN_STRING('CAST(typeContrat AS STRING)') }}                                       AS code_contrat,
    {{ PARSE_CONTRAT(CLEAN_STRING('CAST(typeContratLibelle AS STRING)')) }}                 AS contrat,
    {{ CLEAN_STRING('CAST(experienceExige AS STRING)') }}                                   AS experience,
    {{ CLEAN_STRING('CAST(qualificationCode AS STRING)') }}                                 AS qualification,

    COALESCE(
      SAFE_CAST(dt AS DATE),
      SAFE.PARSE_DATE('%Y-%m-%d', CAST(dt AS STRING)),
      SAFE.PARSE_DATE('%Y%m%d',   CAST(dt AS STRING))
    ) AS date_insertion

  FROM {{ source('raw', 'france_travail_offres') }}
),

dedup AS (
  SELECT *
  FROM cleanup
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id
    ORDER BY date_creation DESC NULLS LAST, date_insertion DESC NULLS LAST
  ) = 1
)

SELECT * FROM dedup
