output "notification_channel_ids" {
  description = "Email notification channel IDs (empty map if create_monitoring = false)"
  value       = { for k, v in google_monitoring_notification_channel.email : k => v.id }
}

output "ingestion_alert_policy_name" {
  description = "Alert policy name for ingestion job (null if create_monitoring = false)"
  value       = one(google_monitoring_alert_policy.ingestion_job_failure[*].name)
}

output "dbt_alert_policy_name" {
  description = "Alert policy name for dbt job (null if create_monitoring = false)"
  value       = one(google_monitoring_alert_policy.dbt_job_failure[*].name)
}
