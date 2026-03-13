output "job_name" {
  description = "Cloud Run Job name (null if create_job = false)"
  value       = one(google_cloud_run_v2_job.ingestion[*].name)
}

output "job_id" {
  description = "Cloud Run Job full resource ID (null if create_job = false)"
  value       = one(google_cloud_run_v2_job.ingestion[*].id)
}
