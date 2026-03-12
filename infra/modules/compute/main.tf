resource "google_cloud_run_v2_job" "ingestion" {
  name                = var.job_name
  location            = var.region
  project             = var.project_id

  template {
    template {
      service_account = var.ingestion_service_account_email != "" ? var.ingestion_service_account_email : null
      timeout         = "${var.timeout_seconds}s"
      max_retries     = var.max_retries

      containers {
        image = var.image

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = var.plain_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = var.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }
}

resource "google_project_iam_member" "job_invoker" {
  for_each = toset(var.job_invoker_service_accounts)

  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${each.value}"
}