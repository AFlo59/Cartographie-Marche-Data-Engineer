output "raw_bucket_name" {
  description = "Name of the raw storage bucket"
  value       = module.storage.bucket_name
}

output "raw_bucket_url" {
  description = "URL of the raw storage bucket"
  value       = module.storage.bucket_url
}

output "datasets" {
  description = "BigQuery datasets created for medallion layers"
  value = {
    raw     = module.warehouse.raw_dataset_id
    staging = module.warehouse.staging_dataset_id
    marts   = module.warehouse.marts_dataset_id
  }
}

output "compute_job_name" {
  description = "Cloud Run ingestion job name"
  value       = module.compute.job_name
}

output "scheduler_job_names" {
  description = "Cloud Scheduler job names"
  value       = module.scheduler.job_names
}

output "secret_ids" {
  description = "Secret Manager secret IDs managed by Terraform"
  value       = module.secrets.secret_ids
}
