resource "google_bigquery_dataset" "raw" {
  project    = var.project_id
  dataset_id = var.raw_dataset_id
  location   = var.location
}

resource "google_bigquery_dataset" "staging" {
  project    = var.project_id
  dataset_id = var.staging_dataset_id
  location   = var.location
}

resource "google_bigquery_dataset" "intermediate" {
  project    = var.project_id
  dataset_id = var.intermediate_dataset_id
  location   = var.location
}

resource "google_bigquery_dataset" "marts" {
  project    = var.project_id
  dataset_id = var.marts_dataset_id
  location   = var.location
}

resource "google_bigquery_dataset_iam_member" "ingestion_raw_editor" {
  count = var.ingestion_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.ingestion_service_account}"
}

resource "google_bigquery_dataset_iam_member" "dbt_raw_viewer" {
  count = var.dbt_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${var.dbt_service_account}"
}

resource "google_bigquery_dataset_iam_member" "dbt_staging_editor" {
  count = var.dbt_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.staging.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.dbt_service_account}"
}

resource "google_bigquery_dataset_iam_member" "dbt_intermediate_editor" {
  count = var.dbt_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.intermediate.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.dbt_service_account}"
}

resource "google_bigquery_dataset_iam_member" "dbt_marts_editor" {
  count = var.dbt_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.dbt_service_account}"
}

resource "google_bigquery_dataset_iam_member" "dashboard_marts_viewer" {
  count = var.dashboard_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${var.dashboard_service_account}"
}

# ── External Tables raw → GCS ────────────────────────────────────────────────
# BigQuery lit directement le Parquet depuis GCS : zéro copie, zéro stockage BQ facturé.
# Activer après la première ingestion (create_external_tables = true).
#
# Structure GCS réelle :
#   raw/france_travail/dt=YYYY-MM-DD/offres.parquet   ← Hive-partitioned par jour
#   raw/sirene/YYYY-MM/StockEtablissement.parquet      ← mensuel, wildcard sur YYYY-MM/
#   raw/sirene/YYYY-MM/StockUniteLegale.parquet
#   raw/geo/YYYY-MM/communes.parquet                   ← mensuel, wildcard sur YYYY-MM/
#   raw/geo/YYYY-MM/departements.parquet
#   raw/geo/YYYY-MM/regions.parquet

# ── France Travail ───────────────────────────────────────────────────────────
# Hive-partitioned : dt=YYYY-MM-DD → BQ ajoute automatiquement la colonne `dt`
resource "google_bigquery_table" "raw_france_travail_offres" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "france_travail_offres"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    # Wildcard sur tous les sous-dossiers dt=*
    # dt=* = un seul wildcard — BQ Hive AUTO détecte la colonne `dt` depuis le nom du dossier
    source_uris = ["gs://${var.raw_bucket_name}/${trim(var.raw_france_travail_prefix, "/")}/dt=*/offres.parquet"]

    hive_partitioning_options {
      mode                     = "AUTO"
      source_uri_prefix        = "gs://${var.raw_bucket_name}/${trim(var.raw_france_travail_prefix, "/")}/"
      require_partition_filter = false
    }
  }
}

# ── Sirene ───────────────────────────────────────────────────────────────────
# Wildcard sur le dossier mensuel YYYY-MM/ : toutes les versions historiques lues
resource "google_bigquery_table" "raw_sirene_etablissements" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "sirene_etablissements"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_sirene_prefix, "/")}/*/StockEtablissement.parquet"]
  }
}

resource "google_bigquery_table" "raw_sirene_unites_legales" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "sirene_unites_legales"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_sirene_prefix, "/")}/*/StockUniteLegale.parquet"]
  }
}

# ── Geo ──────────────────────────────────────────────────────────────────────
resource "google_bigquery_table" "raw_geo_communes" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "geo_communes"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_geo_prefix, "/")}/*/communes.parquet"]
  }
}

resource "google_bigquery_table" "raw_geo_departements" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "geo_departements"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_geo_prefix, "/")}/*/departements.parquet"]
  }
}

resource "google_bigquery_table" "raw_geo_regions" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "geo_regions"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_geo_prefix, "/")}/*/regions.parquet"]
  }
}

# ── APEC ─────────────────────────────────────────────────────────────────────
# Hive-partitioned : dt=YYYY-MM-DD → BQ ajoute automatiquement la colonne `dt`
resource "google_bigquery_table" "raw_apec_offres" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "apec_offres"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_apec_prefix, "/")}/dt=*/offres.parquet"]

    hive_partitioning_options {
      mode                     = "AUTO"
      source_uri_prefix        = "gs://${var.raw_bucket_name}/${trim(var.raw_apec_prefix, "/")}/"
      require_partition_filter = false
    }
  }
}

# ── Jooble ──────────────────────────────────────────────────────────────────
# Hive-partitioned : dt=YYYY-MM-DD → BQ ajoute automatiquement la colonne `dt`
resource "google_bigquery_table" "raw_jooble_offres" {
  count = var.create_jooble_external_table && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "jooble_offres"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${trim(var.raw_jooble_prefix, "/")}/dt=*/offres.parquet"]

    hive_partitioning_options {
      mode                     = "AUTO"
      source_uri_prefix        = "gs://${var.raw_bucket_name}/${trim(var.raw_jooble_prefix, "/")}/"
      require_partition_filter = false
    }
  }
}

resource "google_project_iam_member" "ingestion_job_user" {
  count = var.manage_project_job_user_bindings && var.ingestion_service_account != "" ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.ingestion_service_account}"
}

resource "google_project_iam_member" "dbt_job_user" {
  count = var.manage_project_job_user_bindings && var.dbt_service_account != "" ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.dbt_service_account}"
}

resource "google_project_iam_member" "dashboard_job_user" {
  count = var.manage_project_job_user_bindings && var.dashboard_service_account != "" ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.dashboard_service_account}"
}
