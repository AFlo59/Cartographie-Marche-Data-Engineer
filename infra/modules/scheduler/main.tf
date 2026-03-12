locals {
  scheduler_jobs = {
    france_travail = var.france_travail_schedule
    sirene         = var.sirene_schedule
    geo            = var.geo_schedule
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
    retry_count = 3
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
