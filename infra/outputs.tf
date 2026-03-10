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
