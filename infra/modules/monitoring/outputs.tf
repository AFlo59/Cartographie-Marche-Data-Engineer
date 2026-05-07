output "notification_channel_ids" {
  description = "Email notification channel IDs (empty map if create_monitoring = false)"
  value       = { for k, v in google_monitoring_notification_channel.email : k => v.id }
}

output "ingestion_alert_policy_name" {
  description = "Alert policy name for ingestion job (null if create_monitoring = false)"
  value       = var.create_monitoring ? one(google_monitoring_alert_policy.ingestion_job_failure[*].name) : null
}

output "dbt_alert_policy_name" {
  description = "Alert policy name for dbt job (null if create_monitoring = false or dbt_job_name empty)"
  value       = (var.create_monitoring && var.dbt_job_name != "") ? one(google_monitoring_alert_policy.dbt_job_failure[*].name) : null
}
