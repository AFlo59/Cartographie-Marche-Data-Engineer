resource "google_storage_bucket" "raw" {
  name                        = var.bucket_name
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy

  versioning {
    enabled = var.versioning_enabled
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_delete_age_days == null ? [] : [1]

    content {
      condition {
        age = var.lifecycle_delete_age_days
      }
      action {
        type = "Delete"
      }
    }
  }

  # Transition vers NEARLINE après N jours : ~40% d'économie sur le stockage Sirene (plusieurs Go)
  dynamic "lifecycle_rule" {
    for_each = var.nearline_transition_age_days == null ? [] : [1]

    content {
      condition {
        age = var.nearline_transition_age_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }

  # Suppression des anciennes versions des données geo/ (référentiel stable, rotation mensuelle)
  dynamic "lifecycle_rule" {
    for_each = var.geo_prefix_delete_age_days == null ? [] : [1]

    content {
      condition {
        age            = var.geo_prefix_delete_age_days
        matches_prefix = ["raw/geo/"]
      }
      action {
        type = "Delete"
      }
    }
  }
}

resource "google_storage_bucket_iam_member" "ingestion_object_admin" {
  count = var.ingestion_sa_email == "" ? 0 : 1

  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.ingestion_sa_email}"
}
