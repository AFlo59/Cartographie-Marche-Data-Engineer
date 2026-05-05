-- ============================================
-- STAGING
-- ============================================

-- Référence géographique commune + code postal.
-- Cette vue prépare la table géographique de référence à partir des communes,
-- départements et régions. Elle servira de base à toutes les jointures géographiques.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.staging.v_geo_communes_cp` AS
WITH communes_base AS (
  SELECT
    CAST(code AS STRING) AS code_commune,
    UPPER(TRIM(CAST(nom AS STRING))) AS nom_commune,
    CAST(codeDepartement AS STRING) AS code_departement,
    CAST(codeRegion AS STRING) AS code_region,
    SAFE_CAST(population AS INT64) AS population,
    SAFE_CAST(latitude AS FLOAT64) AS latitude,
    SAFE_CAST(longitude AS FLOAT64) AS longitude,
    CAST(codesPostaux AS STRING) AS codes_postaux_raw
  FROM `cartographie-data-engineer-db.raw.ext_communes`
),
communes_exploded AS (
  SELECT
    code_commune,
    nom_commune,
    code_departement,
    code_region,
    population,
    latitude,
    longitude,
    TRIM(cp) AS code_postal
  FROM communes_base,
  UNNEST(SPLIT(REPLACE(REPLACE(codes_postaux_raw, '[', ''), ']', ''), ',')) AS cp
)
SELECT
  c.code_commune,
  c.nom_commune,
  c.code_postal,
  c.code_departement,
  UPPER(TRIM(CAST(d.nom AS STRING))) AS nom_departement,
  c.code_region,
  UPPER(TRIM(CAST(r.nom AS STRING))) AS nom_region,
  c.population,
  c.latitude,
  c.longitude
FROM communes_exploded c
LEFT JOIN `cartographie-data-engineer-db.raw.ext_departements` d
  ON c.code_departement = CAST(d.code AS STRING)
LEFT JOIN `cartographie-data-engineer-db.raw.ext_regions` r
  ON c.code_region = CAST(r.code AS STRING)
WHERE c.code_postal IS NOT NULL
  AND c.code_postal != '';

-- Nettoyage France Travail.
-- Cette vue standardise les offres France Travail, normalise le type de contrat,
-- calcule un scoring technique, et annualise les salaires quand c'est possible.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.staging.v_france_travail_clean` AS
WITH base AS (
  SELECT
    TRIM(CAST(id AS STRING)) AS id_offre,
    TRIM(CAST(intitule AS STRING)) AS intitule,
    TRIM(CAST(description AS STRING)) AS description,
    LOWER(COALESCE(CAST(intitule AS STRING), '')) AS lower_title,
    LOWER(COALESCE(CAST(description AS STRING), '')) AS lower_desc,
    CASE
      WHEN dateCreation IS NULL THEN NULL
      WHEN LENGTH(CAST(dateCreation AS STRING)) >= 19 THEN TIMESTAMP_MICROS(CAST(SAFE_CAST(CAST(dateCreation AS BIGNUMERIC) / 1000 AS INT64) AS INT64))
      WHEN LENGTH(CAST(dateCreation AS STRING)) BETWEEN 16 AND 18 THEN TIMESTAMP_MICROS(SAFE_CAST(CAST(dateCreation AS STRING) AS INT64))
      WHEN LENGTH(CAST(dateCreation AS STRING)) BETWEEN 13 AND 15 THEN TIMESTAMP_MILLIS(SAFE_CAST(CAST(dateCreation AS STRING) AS INT64))
      WHEN LENGTH(CAST(dateCreation AS STRING)) BETWEEN 10 AND 12 THEN TIMESTAMP_SECONDS(SAFE_CAST(CAST(dateCreation AS STRING) AS INT64))
      ELSE NULL
    END AS date_creation,
    CASE
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{5}$') THEN CAST(lieuTravail_codePostal AS STRING)
      WHEN REGEXP_CONTAINS(CAST(lieuTravail_codePostal AS STRING), r'^\d{4}$') THEN CONCAT('0', CAST(lieuTravail_codePostal AS STRING))
      ELSE NULL
    END AS code_postal,
    TRIM(CAST(lieuTravail_commune AS STRING)) AS commune_ft,
    UPPER(TRIM(CAST(lieuTravail_libelle AS STRING))) AS libelle_lieu_travail,
    NULLIF(TRIM(CAST(entreprise_nom AS STRING)), '') AS entreprise_nom,
    REGEXP_REPLACE(TRIM(CAST(entreprise_numeroSiret AS STRING)), r'[^0-9]', '') AS siret,
    SUBSTR(REGEXP_REPLACE(TRIM(CAST(entreprise_numeroSiret AS STRING)), r'[^0-9]', ''), 1, 9) AS siren,
    TRIM(CAST(salaire_libelle AS STRING)) AS salaire_libelle,
    TRIM(CAST(salaire_complement1 AS STRING)) AS salaire_complement1,
    TRIM(CAST(typeContrat AS STRING)) AS type_contrat,
    TRIM(CAST(typeContratLibelle AS STRING)) AS type_contrat_libelle,
    TRIM(CAST(codeROME AS STRING)) AS code_rome,
    TRIM(CAST(appellationlibelle AS STRING)) AS appellation_libelle,
    TRIM(CAST(experienceExige AS STRING)) AS experience_exige,
    TRIM(CAST(qualificationCode AS STRING)) AS qualification_code
  FROM `cartographie-data-engineer-db.raw.ext_france_travail`
),
enriched AS (
  SELECT
    *,
    CASE
      WHEN REGEXP_CONTAINS(lower_title, r'(alternant|alternance|apprentissage|apprenti|contrat pro)') THEN 'Alternance'
      WHEN REGEXP_CONTAINS(lower_title, r'(stage|stagiaire)') THEN 'Stage'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(type_contrat_libelle, '')), r'(cdi|indéterminée|indeterminee)') THEN 'CDI'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(type_contrat_libelle, '')), r'(cdd|interim|intérim|mission|temporaire)') THEN 'CDD/Interim'
      ELSE COALESCE(type_contrat_libelle, type_contrat)
    END AS contract_type_normalized,
    (
      CASE WHEN REGEXP_CONTAINS(lower_title, r'(data engineer|ingenieur.*donnee|ingénieur.*donnée|data ing[eé]|analytics engineer)') THEN 7 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(lower_desc, r'(spark|airflow|kafka|snowflake|bigquery|dbt|python|sql)') THEN 3 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(lower_title, r'(technicien|maintenance|systeme|système|reseau|réseau|industriel|commercial|achat|sav|chantier)') THEN -10 ELSE 0 END
    ) AS relevance_score,
    SAFE_CAST(REPLACE(REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'([0-9]+(?:[.,][0-9]+)?)'), ',', '.') AS FLOAT64) AS raw_sal_1,
    SAFE_CAST(REPLACE(COALESCE(
      REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'à\s*([0-9]+(?:[.,][0-9]+)?)'),
      REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'-\s*([0-9]+(?:[.,][0-9]+)?)')
    ), ',', '.') AS FLOAT64) AS raw_sal_2,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(ANNUEL|ANNU|/AN|PAR AN|YEAR|YR)') THEN 1
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(MENSUEL|MOIS|MONTH)') THEN 12
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(HORAIRE|HEURE|HOUR)') THEN 1820
      ELSE NULL
    END AS salary_multiplier
  FROM base
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_ft,
  libelle_lieu_travail,
  entreprise_nom,
  siret,
  siren,
  salaire_libelle,
  salaire_complement1,
  type_contrat,
  type_contrat_libelle,
  contract_type_normalized,
  code_rome,
  appellation_libelle,
  experience_exige,
  qualification_code,
  raw_sal_1 * salary_multiplier AS salary_min_annual,
  COALESCE(raw_sal_2, raw_sal_1) * salary_multiplier AS salary_max_annual,
  relevance_score,
  CASE
    WHEN relevance_score >= 7 THEN 'High'
    WHEN relevance_score BETWEEN 3 AND 6 THEN 'Medium'
    ELSE 'Low'
  END AS technical_matching_confidence
FROM enriched;

-- Nettoyage APEC.
-- Cette vue standardise les offres APEC, normalise le type de contrat,
-- calcule un scoring technique, et annualise les salaires quand c'est possible.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.staging.v_apec_clean` AS
WITH base AS (
  SELECT
    TRIM(CAST(apec_id AS STRING)) AS id_offre,
    TRIM(CAST(job_title AS STRING)) AS intitule,
    TRIM(CAST(job_description_preview AS STRING)) AS description,
    LOWER(COALESCE(CAST(job_title AS STRING), '')) AS lower_title,
    LOWER(COALESCE(CAST(job_description_preview AS STRING), '')) AS lower_desc,
    CASE
      WHEN published_at IS NULL THEN NULL
      WHEN LENGTH(CAST(published_at AS STRING)) >= 19 THEN TIMESTAMP_MICROS(CAST(SAFE_CAST(CAST(published_at AS BIGNUMERIC) / 1000 AS INT64) AS INT64))
      WHEN LENGTH(CAST(published_at AS STRING)) BETWEEN 16 AND 18 THEN TIMESTAMP_MICROS(SAFE_CAST(CAST(published_at AS STRING) AS INT64))
      WHEN LENGTH(CAST(published_at AS STRING)) BETWEEN 13 AND 15 THEN TIMESTAMP_MILLIS(SAFE_CAST(CAST(published_at AS STRING) AS INT64))
      WHEN LENGTH(CAST(published_at AS STRING)) BETWEEN 10 AND 12 THEN TIMESTAMP_SECONDS(SAFE_CAST(CAST(published_at AS STRING) AS INT64))
      ELSE NULL
    END AS date_creation,
    NULL AS code_postal,
    UPPER(TRIM(CAST(commune AS STRING))) AS commune_apec,
    UPPER(TRIM(CAST(location_text AS STRING))) AS libelle_lieu_travail,
    NULLIF(TRIM(CAST(company_name AS STRING)), '') AS entreprise_nom,
    TRIM(CAST(contract_type AS STRING)) AS type_contrat,
    TRIM(CAST(salary_text AS STRING)) AS salaire_libelle,
    SAFE_CAST(latitude AS FLOAT64) AS latitude_source,
    SAFE_CAST(longitude AS FLOAT64) AS longitude_source,
    TRIM(CAST(departement AS STRING)) AS departement_source,
    TRIM(CAST(detail_url AS STRING)) AS url_source,
    CASE
      WHEN validated_at IS NULL THEN NULL
      WHEN LENGTH(CAST(validated_at AS STRING)) >= 19 THEN TIMESTAMP_MICROS(CAST(SAFE_CAST(CAST(validated_at AS BIGNUMERIC) / 1000 AS INT64) AS INT64))
      WHEN LENGTH(CAST(validated_at AS STRING)) BETWEEN 16 AND 18 THEN TIMESTAMP_MICROS(SAFE_CAST(CAST(validated_at AS STRING) AS INT64))
      WHEN LENGTH(CAST(validated_at AS STRING)) BETWEEN 13 AND 15 THEN TIMESTAMP_MILLIS(SAFE_CAST(CAST(validated_at AS STRING) AS INT64))
      WHEN LENGTH(CAST(validated_at AS STRING)) BETWEEN 10 AND 12 THEN TIMESTAMP_SECONDS(SAFE_CAST(CAST(validated_at AS STRING) AS INT64))
      ELSE NULL
    END AS date_validation,
    TRIM(CAST(source_name AS STRING)) AS source_name
  FROM `cartographie-data-engineer-db.raw.ext_apec`
),
enriched AS (
  SELECT
    *,
    CASE
      WHEN REGEXP_CONTAINS(lower_title, r'(alternant|alternance|apprentissage|apprenti|contrat pro)') THEN 'Alternance'
      WHEN REGEXP_CONTAINS(lower_title, r'(stage|stagiaire)') THEN 'Stage'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(type_contrat, '')), r'(cdi|indéterminée|indeterminee)') THEN 'CDI'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(type_contrat, '')), r'(cdd|interim|intérim|mission|temporaire)') THEN 'CDD/Interim'
      ELSE type_contrat
    END AS contract_type_normalized,
    (
      CASE WHEN REGEXP_CONTAINS(lower_title, r'(data engineer|ingenieur.*donnee|ingénieur.*donnée|data ing[eé]|analytics engineer)') THEN 7 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(lower_desc, r'(spark|airflow|kafka|snowflake|bigquery|dbt|python|sql)') THEN 3 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(lower_title, r'(technicien|maintenance|systeme|système|reseau|réseau|industriel|commercial|achat|sav|chantier)') THEN -10 ELSE 0 END
    ) AS relevance_score,
    SAFE_CAST(REPLACE(REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'([0-9]+(?:[.,][0-9]+)?)'), ',', '.') AS FLOAT64) AS raw_sal_1,
    SAFE_CAST(REPLACE(COALESCE(
      REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'à\s*([0-9]+(?:[.,][0-9]+)?)'),
      REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'-\s*([0-9]+(?:[.,][0-9]+)?)')
    ), ',', '.') AS FLOAT64) AS raw_sal_2,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(ANNUEL|ANNU|/AN|PAR AN|YEAR|YR)') THEN 1
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(MENSUEL|MOIS|MONTH)') THEN 12
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(HORAIRE|HEURE|HOUR)') THEN 1820
      ELSE NULL
    END AS salary_multiplier
  FROM base
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_apec,
  libelle_lieu_travail,
  entreprise_nom,
  type_contrat,
  contract_type_normalized,
  salaire_libelle,
  raw_sal_1 * salary_multiplier AS salary_min_annual,
  COALESCE(raw_sal_2, raw_sal_1) * salary_multiplier AS salary_max_annual,
  relevance_score,
  CASE
    WHEN relevance_score >= 7 THEN 'High'
    WHEN relevance_score BETWEEN 3 AND 6 THEN 'Medium'
    ELSE 'Low'
  END AS technical_matching_confidence,
  latitude_source,
  longitude_source,
  departement_source,
  url_source,
  date_validation,
  source_name
FROM enriched;

-- Nettoyage Jooble.
-- Cette vue standardise les offres Jooble, génère un identifiant technique stable,
-- calcule un scoring technique, normalise le contrat et annualise les salaires.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.staging.v_jooble_clean` AS
WITH base AS (
  SELECT
    CAST(
      FARM_FINGERPRINT(
        CONCAT(
          COALESCE(CAST(title AS STRING), ''),
          '|',
          COALESCE(CAST(company AS STRING), ''),
          '|',
          COALESCE(CAST(location AS STRING), ''),
          '|',
          COALESCE(CAST(link AS STRING), '')
        )
      ) AS STRING
    ) AS id_offre,
    TRIM(CAST(title AS STRING)) AS intitule,
    TRIM(CAST(snippet AS STRING)) AS description,
    LOWER(COALESCE(CAST(title AS STRING), '')) AS lower_title,
    LOWER(COALESCE(CAST(snippet AS STRING), '')) AS lower_desc,
    CASE
      WHEN updated_dt IS NULL THEN NULL
      WHEN LENGTH(CAST(updated_dt AS STRING)) >= 19 THEN TIMESTAMP_MICROS(CAST(SAFE_CAST(CAST(updated_dt AS BIGNUMERIC) / 1000 AS INT64) AS INT64))
      WHEN LENGTH(CAST(updated_dt AS STRING)) BETWEEN 16 AND 18 THEN TIMESTAMP_MICROS(SAFE_CAST(CAST(updated_dt AS STRING) AS INT64))
      WHEN LENGTH(CAST(updated_dt AS STRING)) BETWEEN 13 AND 15 THEN TIMESTAMP_MILLIS(SAFE_CAST(CAST(updated_dt AS STRING) AS INT64))
      WHEN LENGTH(CAST(updated_dt AS STRING)) BETWEEN 10 AND 12 THEN TIMESTAMP_SECONDS(SAFE_CAST(CAST(updated_dt AS STRING) AS INT64))
      ELSE NULL
    END AS date_creation,
    CASE
      WHEN REGEXP_CONTAINS(CAST(location AS STRING), r'\b\d{5}\b') THEN REGEXP_EXTRACT(CAST(location AS STRING), r'(\d{5})')
      ELSE NULL
    END AS code_postal,
    UPPER(TRIM(CAST(location AS STRING))) AS libelle_lieu_travail,
    NULL AS commune_jooble,
    NULLIF(TRIM(CAST(company AS STRING)), '') AS entreprise_nom,
    TRIM(CAST(type AS STRING)) AS type_contrat,
    TRIM(CAST(salary AS STRING)) AS salaire_libelle,
    TRIM(CAST(source AS STRING)) AS source_name,
    TRIM(CAST(link AS STRING)) AS url_source
  FROM `cartographie-data-engineer-db.raw.ext_jooble`
),
enriched AS (
  SELECT
    *,
    CASE
      WHEN REGEXP_CONTAINS(lower_title, r'(alternant|alternance|apprentissage|apprenti|contrat pro)') THEN 'Alternance'
      WHEN REGEXP_CONTAINS(lower_title, r'(stage|stagiaire)') THEN 'Stage'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(type_contrat, '')), r'(cdi|permanent|full time permanent)') THEN 'CDI'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(type_contrat, '')), r'(cdd|interim|temporary|contract|fixed term)') THEN 'CDD/Interim'
      ELSE type_contrat
    END AS contract_type_normalized,
    (
      CASE WHEN REGEXP_CONTAINS(lower_title, r'(data engineer|ingenieur.*donnee|ingénieur.*donnée|data ing[eé]|analytics engineer)') THEN 7 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(lower_desc, r'(spark|airflow|kafka|snowflake|bigquery|dbt|python|sql)') THEN 3 ELSE 0 END +
      CASE WHEN REGEXP_CONTAINS(lower_title, r'(technicien|maintenance|systeme|système|reseau|réseau|industriel|commercial|achat|sav|chantier)') THEN -10 ELSE 0 END
    ) AS relevance_score,
    SAFE_CAST(REPLACE(REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'([0-9]+(?:[.,][0-9]+)?)'), ',', '.') AS FLOAT64) AS raw_sal_1,
    SAFE_CAST(REPLACE(COALESCE(
      REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'à\s*([0-9]+(?:[.,][0-9]+)?)'),
      REGEXP_EXTRACT(COALESCE(salaire_libelle, ''), r'-\s*([0-9]+(?:[.,][0-9]+)?)')
    ), ',', '.') AS FLOAT64) AS raw_sal_2,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(ANNUEL|ANNU|/AN|PAR AN|YEAR|YR)') THEN 1
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(MENSUEL|MOIS|MONTH)') THEN 12
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(salaire_libelle, '')), r'(HORAIRE|HEURE|HOUR)') THEN 1820
      ELSE NULL
    END AS salary_multiplier
  FROM base
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_jooble,
  libelle_lieu_travail,
  entreprise_nom,
  type_contrat,
  contract_type_normalized,
  salaire_libelle,
  raw_sal_1 * salary_multiplier AS salary_min_annual,
  COALESCE(raw_sal_2, raw_sal_1) * salary_multiplier AS salary_max_annual,
  relevance_score,
  CASE
    WHEN relevance_score >= 7 THEN 'High'
    WHEN relevance_score BETWEEN 3 AND 6 THEN 'Medium'
    ELSE 'Low'
  END AS technical_matching_confidence,
  source_name,
  url_source
FROM enriched;

-- Nettoyage SIRENE unité légale.
-- Cette vue standardise les unités légales SIRENE et conserve uniquement
-- les entreprises diffusables et actives.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.staging.v_sirene_unite_legale_clean` AS
SELECT
  LPAD(TRIM(CAST(siren AS STRING)), 9, '0') AS siren,
  NULLIF(TRIM(CAST(denominationUniteLegale AS STRING)), '') AS denomination_unite_legale,
  UPPER(TRIM(CAST(denominationUniteLegale AS STRING))) AS denomination_unite_legale_norm,
  TRIM(CAST(etatAdministratifUniteLegale AS STRING)) AS etat_administratif_unite_legale,
  TRIM(CAST(categorieJuridiqueUniteLegale AS STRING)) AS categorie_juridique_unite_legale,
  TRIM(CAST(activitePrincipaleUniteLegale AS STRING)) AS code_naf_unite_legale,
  TRIM(CAST(categorieEntreprise AS STRING)) AS categorie_entreprise,
  TRIM(CAST(caractereEmployeurUniteLegale AS STRING)) AS caractere_employeur_unite_legale,
  TRIM(CAST(statutDiffusionUniteLegale AS STRING)) AS statut_diffusion_unite_legale
FROM `cartographie-data-engineer-db.raw.ext_StockUniteLegale`
WHERE TRIM(CAST(statutDiffusionUniteLegale AS STRING)) = 'O'
  AND TRIM(CAST(etatAdministratifUniteLegale AS STRING)) = 'A';

-- Nettoyage SIRENE établissement.
-- Cette vue standardise les établissements SIRENE et conserve uniquement
-- les établissements diffusables et actifs.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.staging.v_sirene_etablissement_clean` AS
SELECT
  REGEXP_REPLACE(TRIM(CAST(siret AS STRING)), r'[^0-9]', '') AS siret,
  LPAD(TRIM(CAST(siren AS STRING)), 9, '0') AS siren,
  TRIM(CAST(etatAdministratifEtablissement AS STRING)) AS etat_administratif_etablissement,
  TRIM(CAST(activitePrincipaleEtablissement AS STRING)) AS code_naf_etablissement,
  TRIM(CAST(codePostalEtablissement AS STRING)) AS code_postal_etablissement,
  UPPER(TRIM(CAST(libelleCommuneEtablissement AS STRING))) AS libelle_commune_etablissement,
  TRIM(CAST(codeCommuneEtablissement AS STRING)) AS code_commune_etablissement,
  TRIM(CAST(trancheEffectifsEtablissement AS STRING)) AS tranche_effectifs_etablissement,
  TRIM(CAST(caractereEmployeurEtablissement AS STRING)) AS caractere_employeur_etablissement,
  TRIM(CAST(statutDiffusionEtablissement AS STRING)) AS statut_diffusion_etablissement
FROM `cartographie-data-engineer-db.raw.ext_StockEtablissement`
WHERE TRIM(CAST(statutDiffusionEtablissement AS STRING)) = 'O'
  AND TRIM(CAST(etatAdministratifEtablissement AS STRING)) = 'A';

-- ============================================
-- INTERMEDIATE
-- ============================================

-- Enrichissement géographique France Travail.
-- Cette vue rattache les offres France Travail à la géographie de référence.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_france_travail_geo` AS
WITH candidates AS (
  SELECT
    ft.*,
    g.code_commune,
    g.nom_commune,
    g.code_departement,
    g.nom_departement,
    g.code_region,
    g.nom_region,
    g.population,
    g.latitude,
    g.longitude,
    ROW_NUMBER() OVER (
      PARTITION BY ft.id_offre
      ORDER BY
        CASE
          WHEN ft.commune_ft = g.code_commune THEN 1
          WHEN UPPER(TRIM(ft.libelle_lieu_travail)) = g.nom_commune THEN 2
          WHEN UPPER(TRIM(ft.commune_ft)) = g.nom_commune THEN 3
          ELSE 4
        END,
        g.population DESC
    ) AS rn
  FROM `cartographie-data-engineer-db.staging.v_france_travail_clean` ft
  LEFT JOIN `cartographie-data-engineer-db.staging.v_geo_communes_cp` g
    ON ft.code_postal = g.code_postal
   AND (
        ft.commune_ft = g.code_commune
        OR UPPER(TRIM(ft.libelle_lieu_travail)) = g.nom_commune
        OR UPPER(TRIM(ft.commune_ft)) = g.nom_commune
       )
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_ft,
  libelle_lieu_travail,
  entreprise_nom,
  siret,
  siren,
  salaire_libelle,
  salaire_complement1,
  type_contrat,
  type_contrat_libelle,
  contract_type_normalized,
  code_rome,
  appellation_libelle,
  experience_exige,
  qualification_code,
  salary_min_annual,
  salary_max_annual,
  relevance_score,
  technical_matching_confidence,
  code_commune,
  nom_commune,
  code_departement,
  nom_departement,
  code_region,
  nom_region,
  latitude,
  longitude
FROM candidates
WHERE rn = 1;

-- Enrichissement géographique APEC.
-- Cette vue rattache les offres APEC à la géographie de référence
-- via commune, département et éventuellement code postal.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_apec_geo` AS
WITH candidates AS (
  SELECT
    a.*,
    g.code_commune,
    g.nom_commune,
    g.code_departement,
    g.nom_departement,
    g.code_region,
    g.nom_region,
    g.population,
    g.latitude,
    g.longitude,
    ROW_NUMBER() OVER (
      PARTITION BY a.id_offre
      ORDER BY g.population DESC
    ) AS rn
  FROM `cartographie-data-engineer-db.staging.v_apec_clean` a
  LEFT JOIN `cartographie-data-engineer-db.staging.v_geo_communes_cp` g
    ON a.commune_apec = g.nom_commune
   AND (
        CAST(a.departement_source AS STRING) = CAST(g.code_departement AS STRING)
        OR UPPER(TRIM(CAST(a.departement_source AS STRING))) = UPPER(TRIM(CAST(g.nom_departement AS STRING)))
        OR CAST(a.code_postal AS STRING) = CAST(g.code_postal AS STRING)
       )
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_apec,
  libelle_lieu_travail,
  entreprise_nom,
  type_contrat,
  contract_type_normalized,
  salaire_libelle,
  salary_min_annual,
  salary_max_annual,
  relevance_score,
  technical_matching_confidence,
  latitude_source,
  longitude_source,
  departement_source,
  url_source,
  date_validation,
  source_name,
  code_commune,
  nom_commune,
  code_departement,
  nom_departement,
  code_region,
  nom_region,
  latitude,
  longitude
FROM candidates
WHERE rn = 1;

-- Enrichissement géographique Jooble.
-- Cette vue rattache les offres Jooble à la géographie de référence
-- via code postal et libellé de localisation.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_jooble_geo` AS
WITH candidates AS (
  SELECT
    j.*,
    g.code_commune,
    g.nom_commune,
    g.code_departement,
    g.nom_departement,
    g.code_region,
    g.nom_region,
    g.population,
    g.latitude,
    g.longitude,
    ROW_NUMBER() OVER (
      PARTITION BY j.id_offre
      ORDER BY
        CASE
          WHEN j.code_postal IS NOT NULL AND j.code_postal = g.code_postal THEN 1
          WHEN UPPER(TRIM(j.libelle_lieu_travail)) LIKE CONCAT('%', g.nom_commune, '%') THEN 2
          ELSE 3
        END,
        g.population DESC
    ) AS rn
  FROM `cartographie-data-engineer-db.staging.v_jooble_clean` j
  LEFT JOIN `cartographie-data-engineer-db.staging.v_geo_communes_cp` g
    ON (
         j.code_postal IS NOT NULL
         AND j.code_postal = g.code_postal
       )
    OR (
         j.libelle_lieu_travail IS NOT NULL
         AND UPPER(TRIM(j.libelle_lieu_travail)) LIKE CONCAT('%', g.nom_commune, '%')
       )
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_jooble,
  libelle_lieu_travail,
  entreprise_nom,
  type_contrat,
  contract_type_normalized,
  salaire_libelle,
  salary_min_annual,
  salary_max_annual,
  relevance_score,
  technical_matching_confidence,
  source_name,
  url_source,
  code_commune,
  nom_commune,
  code_departement,
  nom_departement,
  code_region,
  nom_region,
  latitude,
  longitude
FROM candidates
WHERE rn = 1;

-- Référence entreprise SIRENE enrichie.
-- Cette vue reconstitue la référence entreprise complète en joignant
-- établissement et unité légale.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_sirene_entreprise_enriched` AS
SELECT
  e.siret,
  e.siren,
  u.denomination_unite_legale,
  u.denomination_unite_legale_norm,
  u.etat_administratif_unite_legale,
  u.categorie_juridique_unite_legale,
  u.code_naf_unite_legale,
  u.categorie_entreprise,
  u.caractere_employeur_unite_legale,
  e.etat_administratif_etablissement,
  e.code_naf_etablissement,
  e.code_postal_etablissement,
  e.libelle_commune_etablissement,
  e.code_commune_etablissement,
  e.tranche_effectifs_etablissement,
  e.caractere_employeur_etablissement
FROM `cartographie-data-engineer-db.staging.v_sirene_etablissement_clean` e
LEFT JOIN `cartographie-data-engineer-db.staging.v_sirene_unite_legale_clean` u
  ON e.siren = u.siren;

-- Normalisation des noms entreprise SIRENE.
-- Cette vue prépare une clé textuelle homogène de nom d’entreprise
-- pour améliorer les rapprochements avec les offres.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_sirene_entreprise_normalized` AS
SELECT
  siret,
  siren,
  denomination_unite_legale,
  TRIM(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          UPPER(NORMALIZE(COALESCE(denomination_unite_legale, ''), NFD)),
          r'\p{M}',
          ''
        ),
        r"[-\"'_]",
        ' '
      ),
      r'\s+',
      ' '
    )
  ) AS entreprise_nom_norm,
  etat_administratif_unite_legale,
  categorie_juridique_unite_legale,
  code_naf_unite_legale,
  categorie_entreprise,
  caractere_employeur_unite_legale,
  etat_administratif_etablissement,
  code_naf_etablissement,
  code_postal_etablissement,
  libelle_commune_etablissement,
  code_commune_etablissement,
  tranche_effectifs_etablissement,
  caractere_employeur_etablissement
FROM `cartographie-data-engineer-db.intermediate.v_sirene_entreprise_enriched`;

-- Jointure entreprise France Travail → SIRENE.
-- Cette vue rapproche les offres France Travail des entreprises SIRENE
-- par SIRET ou par nom normalisé + géographie.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_france_travail_entreprise` AS
WITH ft_base AS (
  SELECT
    ft.*,
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            UPPER(NORMALIZE(COALESCE(ft.entreprise_nom, ''), NFD)),
            r'\p{M}',
            ''
          ),
          r"[-\"'_]",
          ' '
        ),
        r'\s+',
        ' '
      )
    ) AS entreprise_nom_norm
  FROM `cartographie-data-engineer-db.intermediate.v_france_travail_geo` ft
),
candidates AS (
  SELECT
    ft.*,
    s.siret AS siret_sirene,
    s.siren AS siren_sirene,
    s.denomination_unite_legale,
    s.entreprise_nom_norm AS entreprise_nom_norm_sirene,
    s.categorie_juridique_unite_legale,
    s.code_naf_unite_legale,
    s.code_naf_etablissement,
    s.categorie_entreprise,
    s.tranche_effectifs_etablissement,
    s.code_postal_etablissement,
    s.libelle_commune_etablissement,
    s.code_commune_etablissement,
    ROW_NUMBER() OVER (
      PARTITION BY ft.id_offre
      ORDER BY
        CASE
          WHEN ft.siret IS NOT NULL AND ft.siret != '' AND ft.siret = s.siret THEN 1
          WHEN ft.entreprise_nom_norm = s.entreprise_nom_norm
               AND ft.code_postal = s.code_postal_etablissement THEN 2
          WHEN ft.entreprise_nom_norm = s.entreprise_nom_norm
               AND ft.code_commune = s.code_commune_etablissement THEN 3
          WHEN ft.entreprise_nom_norm = s.entreprise_nom_norm
               AND ft.nom_commune = s.libelle_commune_etablissement THEN 4
          WHEN ft.entreprise_nom_norm = s.entreprise_nom_norm THEN 5
          ELSE 99
        END
    ) AS rn
  FROM ft_base ft
  LEFT JOIN `cartographie-data-engineer-db.intermediate.v_sirene_entreprise_normalized` s
    ON (
         ft.siret IS NOT NULL
         AND ft.siret != ''
         AND ft.siret = s.siret
       )
    OR (
         ft.entreprise_nom IS NOT NULL
         AND ft.entreprise_nom != ''
         AND ft.entreprise_nom_norm = s.entreprise_nom_norm
       )
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_ft,
  libelle_lieu_travail,
  entreprise_nom,
  entreprise_nom_norm,
  siret,
  siren,
  salaire_libelle,
  salaire_complement1,
  type_contrat,
  type_contrat_libelle,
  contract_type_normalized,
  code_rome,
  appellation_libelle,
  experience_exige,
  qualification_code,
  salary_min_annual,
  salary_max_annual,
  relevance_score,
  technical_matching_confidence,
  code_commune,
  nom_commune,
  code_departement,
  nom_departement,
  code_region,
  nom_region,
  latitude,
  longitude,
  siret_sirene,
  siren_sirene,
  denomination_unite_legale,
  categorie_juridique_unite_legale,
  code_naf_unite_legale,
  code_naf_etablissement,
  categorie_entreprise,
  tranche_effectifs_etablissement,
  code_postal_etablissement,
  libelle_commune_etablissement,
  code_commune_etablissement
FROM candidates
WHERE rn = 1;

-- Jointure entreprise APEC → SIRENE.
-- Cette vue rapproche les offres APEC des entreprises SIRENE
-- par nom normalisé et appui géographique.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_apec_entreprise` AS
WITH apec_base AS (
  SELECT
    a.*,
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            UPPER(NORMALIZE(COALESCE(a.entreprise_nom, ''), NFD)),
            r'\p{M}',
            ''
          ),
          r"[-\"'_]",
          ' '
        ),
        r'\s+',
        ' '
      )
    ) AS entreprise_nom_norm
  FROM `cartographie-data-engineer-db.intermediate.v_apec_geo` a
),
candidates AS (
  SELECT
    a.*,
    s.siret AS siret_sirene,
    s.siren AS siren_sirene,
    s.denomination_unite_legale,
    s.entreprise_nom_norm AS entreprise_nom_norm_sirene,
    s.categorie_juridique_unite_legale,
    s.code_naf_unite_legale,
    s.code_naf_etablissement,
    s.categorie_entreprise,
    s.tranche_effectifs_etablissement,
    s.code_postal_etablissement,
    s.libelle_commune_etablissement,
    s.code_commune_etablissement,
    ROW_NUMBER() OVER (
      PARTITION BY a.id_offre
      ORDER BY
        CASE
          WHEN a.entreprise_nom_norm = s.entreprise_nom_norm
               AND a.code_postal IS NOT NULL
               AND CAST(a.code_postal AS STRING) = CAST(s.code_postal_etablissement AS STRING) THEN 1
          WHEN a.entreprise_nom_norm = s.entreprise_nom_norm
               AND CAST(a.code_commune AS STRING) = CAST(s.code_commune_etablissement AS STRING) THEN 2
          WHEN a.entreprise_nom_norm = s.entreprise_nom_norm
               AND CAST(a.nom_commune AS STRING) = CAST(s.libelle_commune_etablissement AS STRING) THEN 3
          WHEN a.entreprise_nom_norm = s.entreprise_nom_norm
               AND CAST(a.departement_source AS STRING) = CAST(SUBSTR(s.code_postal_etablissement, 1, 2) AS STRING) THEN 4
          WHEN a.entreprise_nom_norm = s.entreprise_nom_norm THEN 5
          ELSE 99
        END
    ) AS rn
  FROM apec_base a
  LEFT JOIN `cartographie-data-engineer-db.intermediate.v_sirene_entreprise_normalized` s
    ON a.entreprise_nom IS NOT NULL
   AND a.entreprise_nom != ''
   AND a.entreprise_nom_norm = s.entreprise_nom_norm
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_apec,
  libelle_lieu_travail,
  entreprise_nom,
  entreprise_nom_norm,
  type_contrat,
  contract_type_normalized,
  salaire_libelle,
  salary_min_annual,
  salary_max_annual,
  relevance_score,
  technical_matching_confidence,
  latitude_source,
  longitude_source,
  departement_source,
  url_source,
  date_validation,
  source_name,
  code_commune,
  nom_commune,
  code_departement,
  nom_departement,
  code_region,
  nom_region,
  latitude,
  longitude,
  siret_sirene,
  siren_sirene,
  denomination_unite_legale,
  categorie_juridique_unite_legale,
  code_naf_unite_legale,
  code_naf_etablissement,
  categorie_entreprise,
  tranche_effectifs_etablissement,
  code_postal_etablissement,
  libelle_commune_etablissement,
  code_commune_etablissement
FROM candidates
WHERE rn = 1;

-- Jointure entreprise Jooble → SIRENE.
-- Cette vue rapproche les offres Jooble des entreprises SIRENE
-- par nom normalisé et signaux géographiques.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.intermediate.v_jooble_entreprise` AS
WITH jooble_base AS (
  SELECT
    j.*,
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            UPPER(NORMALIZE(COALESCE(j.entreprise_nom, ''), NFD)),
            r'\p{M}',
            ''
          ),
          r"[-\"'_]",
          ' '
        ),
        r'\s+',
        ' '
      )
    ) AS entreprise_nom_norm
  FROM `cartographie-data-engineer-db.intermediate.v_jooble_geo` j
),
candidates AS (
  SELECT
    j.*,
    s.siret AS siret_sirene,
    s.siren AS siren_sirene,
    s.denomination_unite_legale,
    s.entreprise_nom_norm AS entreprise_nom_norm_sirene,
    s.categorie_juridique_unite_legale,
    s.code_naf_unite_legale,
    s.code_naf_etablissement,
    s.categorie_entreprise,
    s.tranche_effectifs_etablissement,
    s.code_postal_etablissement,
    s.libelle_commune_etablissement,
    s.code_commune_etablissement,
    ROW_NUMBER() OVER (
      PARTITION BY j.id_offre
      ORDER BY
        CASE
          WHEN j.entreprise_nom_norm = s.entreprise_nom_norm
               AND j.code_postal IS NOT NULL
               AND CAST(j.code_postal AS STRING) = CAST(s.code_postal_etablissement AS STRING) THEN 1
          WHEN j.entreprise_nom_norm = s.entreprise_nom_norm
               AND j.nom_commune = s.libelle_commune_etablissement THEN 2
          WHEN j.entreprise_nom_norm = s.entreprise_nom_norm
               AND j.libelle_lieu_travail LIKE CONCAT('%', s.libelle_commune_etablissement, '%') THEN 3
          WHEN j.entreprise_nom_norm = s.entreprise_nom_norm THEN 4
          ELSE 99
        END
    ) AS rn
  FROM jooble_base j
  LEFT JOIN `cartographie-data-engineer-db.intermediate.v_sirene_entreprise_normalized` s
    ON j.entreprise_nom IS NOT NULL
   AND j.entreprise_nom != ''
   AND j.entreprise_nom_norm = s.entreprise_nom_norm
)
SELECT
  id_offre,
  intitule,
  description,
  date_creation,
  code_postal,
  commune_jooble,
  libelle_lieu_travail,
  entreprise_nom,
  entreprise_nom_norm,
  type_contrat,
  contract_type_normalized,
  salaire_libelle,
  salary_min_annual,
  salary_max_annual,
  relevance_score,
  technical_matching_confidence,
  source_name,
  url_source,
  code_commune,
  nom_commune,
  code_departement,
  nom_departement,
  code_region,
  nom_region,
  latitude,
  longitude,
  siret_sirene,
  siren_sirene,
  denomination_unite_legale,
  categorie_juridique_unite_legale,
  code_naf_unite_legale,
  code_naf_etablissement,
  categorie_entreprise,
  tranche_effectifs_etablissement,
  code_postal_etablissement,
  libelle_commune_etablissement,
  code_commune_etablissement
FROM candidates
WHERE rn = 1;

-- ============================================
-- MARTS
-- ============================================

-- Vue unifiée finale des offres enrichies.
-- Cette vue rassemble les trois sources d’offres dans un format commun,
-- avec la géographie enrichie, l’entreprise source, l’entreprise SIRENE,
-- les salaires annualisés, le contrat normalisé, le scoring technique,
-- et un niveau de fiabilité de la jointure SIRENE.
CREATE OR REPLACE VIEW `cartographie-data-engineer-db.marts.v_offres_unifiees_enriched` AS

SELECT
  'france_travail' AS source_offre,
  CAST(id_offre AS STRING) AS id_offre,
  CAST(intitule AS STRING) AS intitule,
  CAST(description AS STRING) AS description,
  date_creation,
  CAST(entreprise_nom AS STRING) AS entreprise_nom_source,
  CAST(denomination_unite_legale AS STRING) AS entreprise_nom_sirene,
  CAST(COALESCE(denomination_unite_legale, entreprise_nom) AS STRING) AS entreprise_nom_finale,
  CAST(type_contrat AS STRING) AS type_contrat_source,
  CAST(contract_type_normalized AS STRING) AS type_contrat_normalized,
  CAST(type_contrat_libelle AS STRING) AS type_contrat_libelle,
  CAST(salaire_libelle AS STRING) AS salaire_libelle,
  SAFE_CAST(salary_min_annual AS FLOAT64) AS salary_min_annual,
  SAFE_CAST(salary_max_annual AS FLOAT64) AS salary_max_annual,
  SAFE_CAST(relevance_score AS INT64) AS relevance_score,
  CAST(technical_matching_confidence AS STRING) AS technical_matching_confidence,
  CAST(code_postal AS STRING) AS code_postal,
  CAST(code_commune AS STRING) AS code_commune,
  CAST(nom_commune AS STRING) AS nom_commune,
  CAST(code_departement AS STRING) AS code_departement,
  CAST(nom_departement AS STRING) AS nom_departement,
  CAST(code_region AS STRING) AS code_region,
  CAST(nom_region AS STRING) AS nom_region,
  SAFE_CAST(latitude AS FLOAT64) AS latitude,
  SAFE_CAST(longitude AS FLOAT64) AS longitude,
  CAST(siret_sirene AS STRING) AS siret,
  CAST(siren_sirene AS STRING) AS siren,
  CAST(categorie_juridique_unite_legale AS STRING) AS categorie_juridique_unite_legale,
  CAST(code_naf_unite_legale AS STRING) AS code_naf_unite_legale,
  CAST(code_naf_etablissement AS STRING) AS code_naf_etablissement,
  CAST(categorie_entreprise AS STRING) AS categorie_entreprise,
  CAST(tranche_effectifs_etablissement AS STRING) AS tranche_effectifs_etablissement,
  CASE
    WHEN siret IS NOT NULL
         AND siret != ''
         AND CAST(siret AS STRING) = CAST(siret_sirene AS STRING) THEN 'HIGH'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND code_postal IS NOT NULL
         AND CAST(code_postal AS STRING) = CAST(code_postal_etablissement AS STRING) THEN 'HIGH'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND code_commune IS NOT NULL
         AND CAST(code_commune AS STRING) = CAST(code_commune_etablissement AS STRING) THEN 'MEDIUM'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND siren_sirene IS NOT NULL THEN 'LOW'
    ELSE 'NO_MATCH'
  END AS fiabilite_jointure_sirene
FROM `cartographie-data-engineer-db.intermediate.v_france_travail_entreprise`

UNION ALL

SELECT
  'apec' AS source_offre,
  CAST(id_offre AS STRING) AS id_offre,
  CAST(intitule AS STRING) AS intitule,
  CAST(description AS STRING) AS description,
  date_creation,
  CAST(entreprise_nom AS STRING) AS entreprise_nom_source,
  CAST(denomination_unite_legale AS STRING) AS entreprise_nom_sirene,
  CAST(COALESCE(denomination_unite_legale, entreprise_nom) AS STRING) AS entreprise_nom_finale,
  CAST(type_contrat AS STRING) AS type_contrat_source,
  CAST(contract_type_normalized AS STRING) AS type_contrat_normalized,
  CAST(NULL AS STRING) AS type_contrat_libelle,
  CAST(salaire_libelle AS STRING) AS salaire_libelle,
  SAFE_CAST(salary_min_annual AS FLOAT64) AS salary_min_annual,
  SAFE_CAST(salary_max_annual AS FLOAT64) AS salary_max_annual,
  SAFE_CAST(relevance_score AS INT64) AS relevance_score,
  CAST(technical_matching_confidence AS STRING) AS technical_matching_confidence,
  CAST(code_postal AS STRING) AS code_postal,
  CAST(code_commune AS STRING) AS code_commune,
  CAST(nom_commune AS STRING) AS nom_commune,
  CAST(code_departement AS STRING) AS code_departement,
  CAST(nom_departement AS STRING) AS nom_departement,
  CAST(code_region AS STRING) AS code_region,
  CAST(nom_region AS STRING) AS nom_region,
  SAFE_CAST(latitude AS FLOAT64) AS latitude,
  SAFE_CAST(longitude AS FLOAT64) AS longitude,
  CAST(siret_sirene AS STRING) AS siret,
  CAST(siren_sirene AS STRING) AS siren,
  CAST(categorie_juridique_unite_legale AS STRING) AS categorie_juridique_unite_legale,
  CAST(code_naf_unite_legale AS STRING) AS code_naf_unite_legale,
  CAST(code_naf_etablissement AS STRING) AS code_naf_etablissement,
  CAST(categorie_entreprise AS STRING) AS categorie_entreprise,
  CAST(tranche_effectifs_etablissement AS STRING) AS tranche_effectifs_etablissement,
  CASE
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND code_postal IS NOT NULL
         AND CAST(code_postal AS STRING) = CAST(code_postal_etablissement AS STRING) THEN 'HIGH'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND code_commune IS NOT NULL
         AND CAST(code_commune AS STRING) = CAST(code_commune_etablissement AS STRING) THEN 'MEDIUM'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND siren_sirene IS NOT NULL THEN 'LOW'
    ELSE 'NO_MATCH'
  END AS fiabilite_jointure_sirene
FROM `cartographie-data-engineer-db.intermediate.v_apec_entreprise`

UNION ALL

SELECT
  'jooble' AS source_offre,
  CAST(id_offre AS STRING) AS id_offre,
  CAST(intitule AS STRING) AS intitule,
  CAST(description AS STRING) AS description,
  date_creation,
  CAST(entreprise_nom AS STRING) AS entreprise_nom_source,
  CAST(denomination_unite_legale AS STRING) AS entreprise_nom_sirene,
  CAST(COALESCE(denomination_unite_legale, entreprise_nom) AS STRING) AS entreprise_nom_finale,
  CAST(type_contrat AS STRING) AS type_contrat_source,
  CAST(contract_type_normalized AS STRING) AS type_contrat_normalized,
  CAST(NULL AS STRING) AS type_contrat_libelle,
  CAST(salaire_libelle AS STRING) AS salaire_libelle,
  SAFE_CAST(salary_min_annual AS FLOAT64) AS salary_min_annual,
  SAFE_CAST(salary_max_annual AS FLOAT64) AS salary_max_annual,
  SAFE_CAST(relevance_score AS INT64) AS relevance_score,
  CAST(technical_matching_confidence AS STRING) AS technical_matching_confidence,
  CAST(code_postal AS STRING) AS code_postal,
  CAST(code_commune AS STRING) AS code_commune,
  CAST(nom_commune AS STRING) AS nom_commune,
  CAST(code_departement AS STRING) AS code_departement,
  CAST(nom_departement AS STRING) AS nom_departement,
  CAST(code_region AS STRING) AS code_region,
  CAST(nom_region AS STRING) AS nom_region,
  SAFE_CAST(latitude AS FLOAT64) AS latitude,
  SAFE_CAST(longitude AS FLOAT64) AS longitude,
  CAST(siret_sirene AS STRING) AS siret,
  CAST(siren_sirene AS STRING) AS siren,
  CAST(categorie_juridique_unite_legale AS STRING) AS categorie_juridique_unite_legale,
  CAST(code_naf_unite_legale AS STRING) AS code_naf_unite_legale,
  CAST(code_naf_etablissement AS STRING) AS code_naf_etablissement,
  CAST(categorie_entreprise AS STRING) AS categorie_entreprise,
  CAST(tranche_effectifs_etablissement AS STRING) AS tranche_effectifs_etablissement,
  CASE
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND code_postal IS NOT NULL
         AND CAST(code_postal AS STRING) = CAST(code_postal_etablissement AS STRING) THEN 'HIGH'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND nom_commune IS NOT NULL
         AND CAST(nom_commune AS STRING) = CAST(libelle_commune_etablissement AS STRING) THEN 'MEDIUM'
    WHEN entreprise_nom IS NOT NULL
         AND entreprise_nom != ''
         AND siren_sirene IS NOT NULL THEN 'LOW'
    ELSE 'NO_MATCH'
  END AS fiabilite_jointure_sirene
FROM `cartographie-data-engineer-db.intermediate.v_jooble_entreprise`;