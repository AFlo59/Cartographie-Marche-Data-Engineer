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

variable "ingestion_weekly_schedule" {
  description = "Cron schedule for weekly ingestion (france_travail + apec + jooble)"
  type        = string
  default     = "0 6 * * 1"
}

variable "ingestion_monthly_schedule" {
  description = "Cron schedule for monthly ingestion (sirene + geo)"
  type        = string
  default     = "0 3 1 * *"
}

variable "create_dbt_scheduler" {
  description = "Whether to create the Cloud Scheduler job for dbt"
  type        = bool
  default     = false
}

variable "dbt_job_name" {
  description = "Cloud Run Job name for dbt transformations"
  type        = string
  default     = ""
}

variable "dbt_schedule" {
  description = "Cron schedule for dbt run (after all ingestions)"
  type        = string
  default     = "0 9 * * 1"
}
