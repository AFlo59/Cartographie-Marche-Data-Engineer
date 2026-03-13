variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "bucket_name" {
  description = "Globally unique bucket name"
  type        = string
}

variable "location" {
  description = "Bucket region/location"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable object versioning"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Delete bucket with objects"
  type        = bool
  default     = false
}

variable "lifecycle_delete_age_days" {
  description = "Delete objects older than this many days. Null disables lifecycle rule"
  type        = number
  default     = null
}

variable "nearline_transition_age_days" {
  description = "Transition objects to NEARLINE storage class after N days (~40% cheaper). Null (module default) disables — controlled by root var bucket_nearline_age_days (default 30)."
  type        = number
  default     = null
}

variable "geo_prefix_delete_age_days" {
  description = "Delete objects under geo_prefix after N days. Null (module default) disables — controlled by root var bucket_geo_prefix_delete_age_days (default 90)."
  type        = number
  default     = null
}

variable "geo_prefix" {
  description = "GCS prefix for geo data objects, used in the lifecycle delete rule. Must end with '/'."
  type        = string
  default     = "raw/geo/"
}

variable "ingestion_sa_email" {
  description = "Ingestion service account email for bucket access"
  type        = string
  default     = ""
}

variable "dbt_sa_email" {
  description = "dbt service account email — needs storage.objectViewer to query BigQuery external tables backed by this bucket"
  type        = string
  default     = ""
}
