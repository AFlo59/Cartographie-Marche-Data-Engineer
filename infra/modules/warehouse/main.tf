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

resource "google_bigquery_dataset_iam_member" "dbt_raw_editor" {
  count = var.dbt_service_account == "" ? 0 : 1

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
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
