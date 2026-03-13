resource "google_artifact_registry_repository" "datatalent" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repository_id
  format        = "DOCKER"
  description   = "Docker images for DataTalent pipeline (ingestion + dbt)"
}

resource "google_project_iam_member" "ci_artifact_registry_writer" {
  count = var.ci_service_account_email != "" ? 1 : 0

  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${var.ci_service_account_email}"

  depends_on = [google_artifact_registry_repository.datatalent]
}

resource "google_cloud_run_v2_job" "ingestion" {
  count    = var.create_job ? 1 : 0
  name     = var.job_name
  location = var.region
  project  = var.project_id

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

  lifecycle {
    precondition {
      condition     = trimspace(var.image) != ""
      error_message = "compute_image must be set before enabling create_compute_job (example: europe-west1-docker.pkg.dev/<project>/datatalent/ingestion:latest)."
    }
  }

  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}

data "google_project" "current" {
  project_id = var.project_id
}

# GCP IAM bindings peuvent prendre jusqu'à 90s à se propager.
# Sans ce délai, la création du Cloud Run Job échoue avec 403 sur Artifact Registry.
# Les triggers forcent une re-création du sleep si l'un des bindings IAM change lors d'un
# apply ultérieur — sans triggers, time_sleep resterait en state et ne re-attendrait pas.
# count = create_job : inutile d'attendre si le job n'est pas créé.
resource "time_sleep" "wait_for_iam_propagation" {
  count           = (var.create_job || var.create_dbt_job) ? 1 : 0
  create_duration = "90s"

  triggers = {
    # one() retourne null si count=0 (sa non fourni), on le remplace par "" pour respecter map(string)
    ingestion_iam_id = coalesce(one(google_project_iam_member.ingestion_artifact_registry_reader[*].id), "")
    cloud_run_iam_id = google_project_iam_member.cloud_run_service_agent_artifact_registry_reader.id
    ci_iam_id        = coalesce(one(google_project_iam_member.ci_artifact_registry_writer[*].id), "")
    dbt_iam_id       = coalesce(one(google_project_iam_member.dbt_artifact_registry_reader[*].id), "")
  }

  depends_on = [
    google_project_iam_member.ingestion_artifact_registry_reader,
    google_project_iam_member.cloud_run_service_agent_artifact_registry_reader,
    google_project_iam_member.ci_artifact_registry_writer,
    google_project_iam_member.dbt_artifact_registry_reader,
  ]
}

resource "google_project_iam_member" "ingestion_artifact_registry_reader" {
  count = var.ingestion_service_account_email == "" ? 0 : 1

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${var.ingestion_service_account_email}"
}

resource "google_project_iam_member" "dbt_artifact_registry_reader" {
  count = var.dbt_service_account_email == "" ? 0 : 1

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${var.dbt_service_account_email}"
}

resource "google_project_iam_member" "cloud_run_service_agent_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${data.google_project.current.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_job_iam_member" "job_invoker" {
  for_each = var.create_job ? toset(var.job_invoker_service_accounts) : toset([])

  project  = var.project_id
  name     = var.job_name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${each.value}"

  depends_on = [google_cloud_run_v2_job.ingestion]
}

# ── Cloud Run Job dbt ────────────────────────────────────────────────────────

resource "google_cloud_run_v2_job" "dbt" {
  count    = var.create_dbt_job ? 1 : 0
  name     = var.dbt_job_name
  location = var.region
  project  = var.project_id

  template {
    template {
      service_account = var.dbt_service_account_email != "" ? var.dbt_service_account_email : null
      timeout         = "${var.dbt_timeout_seconds}s"
      max_retries     = var.dbt_max_retries

      containers {
        image = var.dbt_image

        resources {
          limits = {
            cpu    = var.dbt_cpu
            memory = var.dbt_memory
          }
        }

        dynamic "env" {
          for_each = var.dbt_plain_env
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = trimspace(var.dbt_image) != ""
      error_message = "dbt_image must be set before enabling create_dbt_job (example: europe-west1-docker.pkg.dev/<project>/datatalent/dbt:latest)."
    }
  }

  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}