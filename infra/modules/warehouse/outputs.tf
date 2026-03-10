output "raw_dataset_id" {
  description = "Raw dataset ID"
  value       = google_bigquery_dataset.raw.dataset_id
}

output "staging_dataset_id" {
  description = "Staging dataset ID"
  value       = google_bigquery_dataset.staging.dataset_id
}

output "marts_dataset_id" {
  description = "Marts dataset ID"
  value       = google_bigquery_dataset.marts.dataset_id
}
