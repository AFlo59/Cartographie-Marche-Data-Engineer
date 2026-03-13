variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Cloud Run region"
  type        = string
}

variable "job_name" {
  description = "Cloud Run Job name"
  type        = string
}

variable "image" {
  description = "Container image for Cloud Run Job"
  type        = string
}

variable "memory" {
  description = "Memory limit for the job container (e.g. 512Mi)"
  type        = string
  default     = "512Mi"
}

variable "cpu" {
  description = "CPU limit for the job container (e.g. 1)"
  type        = string
  default     = "1"
}

variable "timeout_seconds" {
  description = "Execution timeout in seconds"
  type        = number
  default     = 1800
}

variable "max_retries" {
  description = "Max retries for failed task execution"
  type        = number
  default     = 1
}

variable "ingestion_service_account_email" {
  description = "Service account used at runtime by Cloud Run Job"
  type        = string
  default     = ""
}

variable "job_invoker_service_accounts" {
  description = "Service accounts allowed to trigger job run"
  type        = list(string)
  default     = []
}

variable "plain_env" {
  description = "Plain environment variables injected into the job"
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Map of env var name => Secret Manager secret name"
  type        = map(string)
  default     = {}
}

variable "create_job" {
  description = "Create the Cloud Run Job resource. Set to true only after the container image has been pushed to Artifact Registry (job creation fails if the image does not exist)."
  type        = bool
  default     = false
}

variable "ci_service_account_email" {
  description = "Service account used by CI (WIF) to push Docker images to Artifact Registry"
  type        = string
  default     = ""
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID (Docker)"
  type        = string
  default     = "datatalent"
}

# ── Cloud Run Job dbt ────────────────────────────────────────────────────────

variable "create_dbt_job" {
  description = "Create the dbt Cloud Run Job. Set to true only after the dbt image has been pushed to Artifact Registry."
  type        = bool
  default     = false
}

variable "dbt_job_name" {
  description = "Cloud Run Job name for dbt transformations"
  type        = string
  default     = "datatalent-dbt-job"
}

variable "dbt_image" {
  description = "Container image for the dbt Cloud Run Job"
  type        = string
  default     = ""
}

variable "dbt_service_account_email" {
  description = "Service account used at runtime by the dbt Cloud Run Job"
  type        = string
  default     = ""
}

variable "dbt_memory" {
  description = "Memory limit for the dbt job container"
  type        = string
  default     = "1Gi"
}

variable "dbt_cpu" {
  description = "CPU limit for the dbt job container"
  type        = string
  default     = "1"
}

variable "dbt_timeout_seconds" {
  description = "dbt Cloud Run Job timeout in seconds"
  type        = number
  default     = 1800
}

variable "dbt_max_retries" {
  description = "dbt Cloud Run Job max retries"
  type        = number
  default     = 0
}

variable "dbt_plain_env" {
  description = "Plain environment variables injected into the dbt job"
  type        = map(string)
  default     = {}
}