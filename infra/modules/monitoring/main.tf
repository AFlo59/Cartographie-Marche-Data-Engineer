check "alert_emails_required" {
  assert {
    condition     = !var.create_monitoring || length(var.alert_emails) > 0
    error_message = "create_monitoring = true mais alert_emails est vide — les alert policies seront créées sans destinataires."
  }
}

resource "google_monitoring_notification_channel" "email" {
  for_each = var.create_monitoring ? toset(var.alert_emails) : toset([])

  project      = var.project_id
  display_name = "Pipeline Alerts — ${each.value}"
  type         = "email"

  labels = {
    email_address = each.value
  }
}

resource "google_monitoring_alert_policy" "ingestion_job_failure" {
  count = var.create_monitoring ? 1 : 0

  project      = var.project_id
  display_name = "Cloud Run Job Failure — ${var.ingestion_job_name}"
  combiner     = "OR"

  conditions {
    display_name = "Ingestion job — severity ERROR ou plus"
    condition_matched_log {
      filter = <<-EOT
        resource.type="cloud_run_job"
        resource.labels.project_id="${var.project_id}"
        resource.labels.job_name="${var.ingestion_job_name}"
        severity>=ERROR
      EOT
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "${var.notification_rate_seconds}s"
    }
    auto_close = "86400s"
  }

  notification_channels = [for ch in google_monitoring_notification_channel.email : ch.id]
}

resource "google_monitoring_alert_policy" "dbt_job_failure" {
  count = var.create_monitoring && var.dbt_job_name != "" ? 1 : 0

  project      = var.project_id
  display_name = "Cloud Run Job Failure — ${var.dbt_job_name}"
  combiner     = "OR"

  conditions {
    display_name = "dbt job — severity ERROR ou plus"
    condition_matched_log {
      filter = <<-EOT
        resource.type="cloud_run_job"
        resource.labels.project_id="${var.project_id}"
        resource.labels.job_name="${var.dbt_job_name}"
        severity>=ERROR
      EOT
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "${var.notification_rate_seconds}s"
    }
    auto_close = "86400s"
  }

  notification_channels = [for ch in google_monitoring_notification_channel.email : ch.id]
}
