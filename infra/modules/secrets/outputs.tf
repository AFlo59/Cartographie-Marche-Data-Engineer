output "secret_ids" {
  description = "Secret IDs created"
  value       = [for s in google_secret_manager_secret.secrets : s.secret_id]
}
