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
