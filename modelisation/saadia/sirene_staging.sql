WITH base_unite AS (
  SELECT 
    siren,
    COALESCE(denominationUniteLegale, nomUniteLegale) as official_name,
    categorieEntreprise as company_size_category,
    trancheEffectifsUniteLegale as staff_range_code,
    activitePrincipaleUniteLegale as naf_code,
    economieSocialeSolidaireUniteLegale as is_ess
  FROM `cartographie-data-engineer.raw.sirene_unites_legales`
  WHERE etatAdministratifUniteLegale = 'A'
),
base_etablissement AS (
  SELECT 
    siren,
    siret,
    denominationUsuelleEtablissement as local_name,
    enseigne1Etablissement as brand_name,
    codePostalEtablissement as zip_code,
    libelleCommuneEtablissement as city
  FROM `cartographie-data-engineer.raw.sirene_etablissements`
  WHERE etablissementSiege = TRUE 
)

SELECT * EXCEPT(row_num) FROM (
    SELECT 
      u.*,
      e.local_name,
      e.brand_name,
      e.zip_code,
      e.city,
      UPPER(REGEXP_REPLACE(NORMALIZE(
        COALESCE(e.local_name, e.brand_name, u.official_name), 
        NFD), r"[^\w]", "")) as company_key_norm,
      -- On crée un rang pour ne garder qu'une seule ligne par clé
      ROW_NUMBER() OVER(PARTITION BY UPPER(REGEXP_REPLACE(NORMALIZE(COALESCE(e.local_name, e.brand_name, u.official_name), NFD), r"[^\w]", "")) ORDER BY u.siren DESC) as row_num
    FROM base_unite u
    LEFT JOIN base_etablissement e ON u.siren = e.siren
)
WHERE row_num = 1
LIMIT 100 -- Ajouté pour le test