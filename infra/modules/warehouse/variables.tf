variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "BigQuery datasets location"
  type        = string
}

variable "raw_dataset_id" {
  description = "Dataset ID for raw layer"
  type        = string
  default     = "raw"
}

variable "staging_dataset_id" {
  description = "Dataset ID for staging layer"
  type        = string
  default     = "staging"
}

variable "marts_dataset_id" {
  description = "Dataset ID for marts layer"
  type        = string
  default     = "marts"
}

variable "ingestion_service_account" {
  description = "Service account email for ingestion jobs"
  type        = string
  default     = ""
}

variable "dbt_service_account" {
  description = "Service account email for dbt"
  type        = string
  default     = ""
}

variable "dashboard_service_account" {
  description = "Service account email for dashboard read-only access"
  type        = string
  default     = ""
}

variable "manage_project_job_user_bindings" {
  description = "Whether to manage project-level roles/bigquery.jobUser bindings"
  type        = bool
  default     = true
}

variable "raw_bucket_name" {
  description = "GCS bucket name for raw data. When set, external tables are created in the raw dataset pointing to GCS (avoids BQ storage costs for large datasets like Sirene)."
  type        = string
  default     = ""
}

variable "raw_sirene_prefix" {
  description = "GCS prefix for Sirene raw Parquet files"
  type        = string
  default     = "raw/sirene/"
}

variable "raw_france_travail_prefix" {
  description = "GCS prefix for France Travail raw Parquet files"
  type        = string
  default     = "raw/france_travail/"
}
