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

  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}

data "google_project" "current" {
  project_id = var.project_id
}

# GCP IAM bindings peuvent prendre jusqu'à 60s à se propager.
# Sans ce délai, la création du Cloud Run Job échoue avec 403 sur Artifact Registry.
# Les triggers forcent une re-création du sleep si l'un des bindings IAM change lors d'un
# apply ultérieur — sans triggers, time_sleep resterait en state et ne re-attendrait pas.
resource "time_sleep" "wait_for_iam_propagation" {
  create_duration = "60s"

  triggers = {
    # one() retourne null si count=0 (ingestion_sa non fourni), valide comme trigger
    ingestion_iam_id = one(google_project_iam_member.ingestion_artifact_registry_reader[*].id)
    cloud_run_iam_id = google_project_iam_member.cloud_run_service_agent_artifact_registry_reader.id
  }

  depends_on = [
    google_project_iam_member.ingestion_artifact_registry_reader,
    google_project_iam_member.cloud_run_service_agent_artifact_registry_reader,
  ]
}

resource "google_project_iam_member" "ingestion_artifact_registry_reader" {
  count = var.ingestion_service_account_email == "" ? 0 : 1

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${var.ingestion_service_account_email}"
}

resource "google_project_iam_member" "cloud_run_service_agent_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${data.google_project.current.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_job_iam_member" "job_invoker" {
  for_each = toset(var.job_invoker_service_accounts)

  name     = google_cloud_run_v2_job.ingestion.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${each.value}"
}