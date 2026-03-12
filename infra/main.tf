locals {
  bucket_name_base = lower("${var.project_prefix}-${var.environment}-${var.project_id}-raw")
  bucket_name_default = length(local.bucket_name_base) <= 63 ? local.bucket_name_base : "${substr(local.bucket_name_base, 0, 52)}-${substr(md5(local.bucket_name_base), 0, 10)}"
  bucket_name = var.raw_bucket_name != "" ? var.raw_bucket_name : local.bucket_name_default

  secret_ids = compact([
    var.secret_ft_client_id_name,
    var.secret_ft_client_secret_name,
    var.secret_datagouv_api_key_name
  ])

  compute_secret_env = {
    FT_CLIENT_ID     = var.secret_ft_client_id_name
    FT_CLIENT_SECRET = var.secret_ft_client_secret_name
  }

  compute_secret_env_optional = var.secret_datagouv_api_key_name != "" ? {
    DATAGOUV_API_KEY = var.secret_datagouv_api_key_name
  } : {}

  scheduler_service_account_email = var.scheduler_service_account_email != "" ? var.scheduler_service_account_email : var.ingestion_service_account_email
}

check "required_service_accounts" {
  assert {
    condition     = trimspace(var.ingestion_service_account_email) != ""
    error_message = "ingestion_service_account_email is required."
  }

  assert {
    condition     = trimspace(var.dbt_service_account_email) != ""
    error_message = "dbt_service_account_email is required."
  }

  assert {
    condition     = trimspace(var.dashboard_service_account_email) != ""
    error_message = "dashboard_service_account_email is required."
  }
}

check "scheduler_service_account_resolved" {
  assert {
    condition     = trimspace(local.scheduler_service_account_email) != ""
    error_message = "Set scheduler_service_account_email or ingestion_service_account_email (fallback) to a non-empty value."
  }
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
  manage_project_job_user_bindings = var.manage_project_job_user_bindings
}

module "secrets" {
  source = "./modules/secrets"

  project_id                      = var.project_id
  secret_ids                      = local.secret_ids
  ingestion_service_account_email = var.ingestion_service_account_email
}

module "compute" {
  source = "./modules/compute"

  project_id                      = var.project_id
  region                          = var.region
  job_name                        = var.compute_job_name
  image                           = var.compute_image
  memory                          = var.compute_memory
  cpu                             = var.compute_cpu
  timeout_seconds                 = var.compute_timeout_seconds
  max_retries                     = var.compute_max_retries
  ingestion_service_account_email = var.ingestion_service_account_email
  job_invoker_service_accounts    = compact([local.scheduler_service_account_email])

  plain_env = {
    GCP_PROJECT_ID                  = var.project_id
    INGESTION_RAW_BUCKET            = local.bucket_name
    INGESTION_FRANCE_TRAVAIL_PREFIX = var.ingestion_france_travail_prefix
    INGESTION_SIRENE_PREFIX         = var.ingestion_sirene_prefix
    INGESTION_GEO_PREFIX            = var.ingestion_geo_prefix
  }

  secret_env = merge(local.compute_secret_env, local.compute_secret_env_optional)

  depends_on = [module.secrets]
}

module "scheduler" {
  source = "./modules/scheduler"

  project_id                      = var.project_id
  region                          = var.region
  compute_job_name                = module.compute.job_name
  scheduler_service_account_email = local.scheduler_service_account_email
  job_name_prefix                 = var.scheduler_job_name_prefix
  time_zone                       = var.scheduler_time_zone
  france_travail_schedule         = var.scheduler_france_travail_schedule
  sirene_schedule                 = var.scheduler_sirene_schedule
  geo_schedule                    = var.scheduler_geo_schedule
}
