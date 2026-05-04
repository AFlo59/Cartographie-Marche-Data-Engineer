locals {
  scheduler_jobs = {
    weekly  = var.ingestion_weekly_schedule
    monthly = var.ingestion_monthly_schedule
  }
}

resource "google_cloud_scheduler_job" "dbt" {
  count = var.create_dbt_scheduler ? 1 : 0

  name             = "datatalent-dbt"
  description      = "Trigger Cloud Run Job dbt (transformations hebdomadaires)"
  schedule         = var.dbt_schedule
  time_zone        = var.time_zone
  project          = var.project_id
  region           = var.region
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${var.dbt_job_name}:run"
    http_method = "POST"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode("{}")

    oauth_token {
      service_account_email = var.scheduler_service_account_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}

resource "google_cloud_scheduler_job" "ingestion" {
  for_each = local.scheduler_jobs

  name             = "${var.job_name_prefix}-${each.key}"
  description      = "Trigger Cloud Run Job for source ${each.key}"
  schedule         = each.value
  time_zone        = var.time_zone
  project          = var.project_id
  region           = var.region
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${var.compute_job_name}:run"
    http_method = "POST"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      overrides = {
        containerOverrides = [{
          env = [{
            name  = "INGESTION_SOURCE"
            value = each.key
          }]
        }]
      }
    }))

    oauth_token {
      service_account_email = var.scheduler_service_account_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
