output "job_names" {
  description = "Cloud Scheduler job names"
  value       = [for j in google_cloud_scheduler_job.ingestion : j.name]
}
