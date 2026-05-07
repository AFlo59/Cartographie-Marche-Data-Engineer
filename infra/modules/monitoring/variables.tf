variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "create_monitoring" {
  description = "Create Cloud Monitoring alert policies and email notification channels"
  type        = bool
  default     = false
}

variable "alert_emails" {
  description = "List of email addresses to receive pipeline failure alerts. Required when create_monitoring = true."
  type        = list(string)
  default     = []
}

variable "ingestion_job_name" {
  description = "Cloud Run Job name for ingestion"
  type        = string
  default     = "datatalent-ingestion-job"
}

variable "dbt_job_name" {
  description = "Cloud Run Job name for dbt. Empty string disables the dbt alert."
  type        = string
  default     = ""
}

variable "notification_rate_seconds" {
  description = "Minimum interval in seconds between successive notifications for the same alert"
  type        = number
  default     = 300
}
