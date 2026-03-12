variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "secret_ids" {
  description = "Secret containers to create"
  type        = list(string)
}

variable "ingestion_service_account_email" {
  description = "Service account granted secretAccessor"
  type        = string
  default     = ""
}
