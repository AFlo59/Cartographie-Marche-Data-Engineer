locals {
  bucket_name = "${var.project_prefix}-${var.environment}-${var.project_id}-raw"
}

module "storage" {
  source = "./modules/storage"

  project_id                = var.project_id
  bucket_name               = local.bucket_name
  location                  = var.region
  versioning_enabled        = var.bucket_versioning_enabled
  force_destroy             = var.bucket_force_destroy
  lifecycle_delete_age_days = var.bucket_lifecycle_delete_age_days
  ingestion_sa_email        = var.ingestion_service_account_email
}

module "warehouse" {
  source = "./modules/warehouse"

  project_id                   = var.project_id
  location                     = var.location
  raw_dataset_id               = var.raw_dataset_id
  staging_dataset_id           = var.staging_dataset_id
  marts_dataset_id             = var.marts_dataset_id
  ingestion_service_account    = var.ingestion_service_account_email
  dbt_service_account          = var.dbt_service_account_email
  dashboard_service_account    = var.dashboard_service_account_email
}
