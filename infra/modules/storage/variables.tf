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
  description = "Transition objects to NEARLINE storage class after N days (~40% cheaper). Null disables."
  type        = number
  default     = null
}

variable "geo_prefix_delete_age_days" {
  description = "Delete objects under raw/geo/ prefix after N days (stable ref data, no need to keep history). Null disables."
  type        = number
  default     = null
}

variable "ingestion_sa_email" {
  description = "Ingestion service account email for bucket access"
  type        = string
  default     = ""
}
