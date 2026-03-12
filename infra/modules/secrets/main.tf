resource "google_secret_manager_secret" "secrets" {
  for_each = toset(var.secret_ids)

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "ingestion_accessor" {
  for_each = var.ingestion_service_account_email == "" ? {} : google_secret_manager_secret.secrets

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.ingestion_service_account_email}"
}
