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
