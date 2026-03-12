variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for regional services"
  type        = string
  default     = "europe-west1"
}

variable "location" {
  description = "Location for BigQuery datasets"
  type        = string
  default     = "EU"
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "project_prefix" {
  description = "Prefix used for resource naming"
  type        = string
  default     = "datatalent"
}

variable "raw_bucket_name" {
  description = "Optional explicit bucket name override for raw storage (must be globally unique and GCS-compliant)"
  type        = string
  default     = ""
}

variable "bucket_versioning_enabled" {
  description = "Enable object versioning on raw bucket"
  type        = bool
  default     = true
}

variable "bucket_force_destroy" {
  description = "Allow bucket deletion with objects inside"
  type        = bool
  default     = false
}

variable "bucket_lifecycle_delete_age_days" {
  description = "Delete objects older than this many days. Set null to disable lifecycle delete rule"
  type        = number
  default     = 365
}

variable "ingestion_service_account_email" {
  description = "Service account used by ingestion jobs"
  type        = string
  default     = ""
}

variable "dbt_service_account_email" {
  description = "Service account used by dbt transformations"
  type        = string
  default     = ""
}

variable "dashboard_service_account_email" {
  description = "Service account used by BI/dashboard tools"
  type        = string
  default     = ""
}

variable "raw_dataset_id" {
  description = "BigQuery dataset ID for raw layer"
  type        = string
  default     = "raw"
}

variable "staging_dataset_id" {
  description = "BigQuery dataset ID for staging layer"
  type        = string
  default     = "staging"
}

variable "marts_dataset_id" {
  description = "BigQuery dataset ID for marts layer"
  type        = string
  default     = "marts"
}

variable "ingestion_france_travail_prefix" {
  description = "Prefix for France Travail raw files"
  type        = string
  default     = "raw/france_travail/"
}

variable "ingestion_sirene_prefix" {
  description = "Prefix for Sirene raw files"
  type        = string
  default     = "raw/sirene/"
}

variable "ingestion_geo_prefix" {
  description = "Prefix for Geo API raw files"
  type        = string
  default     = "raw/geo/"
}

variable "compute_job_name" {
  description = "Cloud Run Job name for ingestion"
  type        = string
  default     = "datatalent-ingestion-job"
}

variable "compute_image" {
  description = "Container image used by Cloud Run Job"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/job:latest"
}

variable "compute_memory" {
  description = "Memory for Cloud Run Job container"
  type        = string
  default     = "512Mi"
}

variable "compute_cpu" {
  description = "CPU for Cloud Run Job container"
  type        = string
  default     = "1"
}

variable "compute_timeout_seconds" {
  description = "Cloud Run Job timeout in seconds"
  type        = number
  default     = 1800
}

variable "compute_max_retries" {
  description = "Cloud Run Job max retries"
  type        = number
  default     = 1
}

variable "scheduler_service_account_email" {
  description = "Service account used by Cloud Scheduler to call Run API"
  type        = string
  default     = ""
}

variable "scheduler_job_name_prefix" {
  description = "Prefix for scheduler jobs"
  type        = string
  default     = "datatalent-ingestion"
}

variable "scheduler_time_zone" {
  description = "Timezone for scheduler jobs"
  type        = string
  default     = "Europe/Paris"
}

variable "scheduler_france_travail_schedule" {
  description = "Cron schedule for France Travail ingestion"
  type        = string
  default     = "0 6 * * *"
}

variable "scheduler_sirene_schedule" {
  description = "Cron schedule for Sirene ingestion"
  type        = string
  default     = "0 3 1 * *"
}

variable "scheduler_geo_schedule" {
  description = "Cron schedule for Geo ingestion"
  type        = string
  default     = "0 4 1 * *"
}

variable "secret_ft_client_id_name" {
  description = "Secret Manager secret id for France Travail client id"
  type        = string
  default     = "FT_CLIENT_ID"
}

variable "secret_ft_client_secret_name" {
  description = "Secret Manager secret id for France Travail client secret"
  type        = string
  default     = "FT_CLIENT_SECRET"
}

variable "secret_datagouv_api_key_name" {
  description = "Secret Manager secret id for data.gouv API key"
  type        = string
  default     = "DATAGOUV_API_KEY"
}
