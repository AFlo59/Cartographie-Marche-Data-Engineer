variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Cloud Scheduler region"
  type        = string
}

variable "compute_job_name" {
  description = "Cloud Run Job name to trigger"
  type        = string
}

variable "scheduler_service_account_email" {
  description = "Service account used by Cloud Scheduler for OAuth token"
  type        = string
}

variable "job_name_prefix" {
  description = "Prefix for Cloud Scheduler job names"
  type        = string
  default     = "datatalent-ingestion"
}

variable "time_zone" {
  description = "Timezone used by Cloud Scheduler"
  type        = string
  default     = "Europe/Paris"
}

variable "france_travail_schedule" {
  description = "Cron schedule for France Travail ingestion"
  type        = string
  default     = "0 6 * * *"
}

variable "sirene_schedule" {
  description = "Cron schedule for Sirene ingestion"
  type        = string
  default     = "0 3 1 * *"
}

variable "geo_schedule" {
  description = "Cron schedule for Geo API ingestion"
  type        = string
  default     = "0 4 1 * *"
}
