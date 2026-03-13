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

# External Tables raw → GCS
# BigQuery lit directement le Parquet depuis GCS : zéro copie, zéro stockage BQ facturé.
# Création conditionnée par create_external_tables = true (défaut false) :
# BQ autodetect requiert au moins un fichier Parquet présent dans GCS à la création.
# Activer après la première ingestion.

resource "google_bigquery_table" "raw_sirene_etablissements" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "sirene_etablissements"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${var.raw_sirene_prefix}etablissements/*.parquet"]
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
    source_uris   = ["gs://${var.raw_bucket_name}/${var.raw_sirene_prefix}unites_legales/*.parquet"]
  }
}

resource "google_bigquery_table" "raw_france_travail_offres" {
  count = var.create_external_tables && var.raw_bucket_name != "" ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "france_travail_offres"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["gs://${var.raw_bucket_name}/${var.raw_france_travail_prefix}*.parquet"]
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
