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

  # Purge globale des objets très anciens (filet de sécurité)
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

  # --- Purge par source (garder latest + 1 run précédent) ---

  # france_travail : partition quotidienne dt=YYYY-MM-DD — purge après N jours
  # Garde uniquement les N derniers jours de partitions.
  dynamic "lifecycle_rule" {
    for_each = var.france_travail_prefix_delete_age_days == null ? [] : [1]

    content {
      condition {
        age            = var.france_travail_prefix_delete_age_days
        matches_prefix = [var.france_travail_prefix]
      }
      action {
        type = "Delete"
      }
    }
  }

  # sirene : snapshot mensuel YYYY-MM/ — purge après N jours (31j = 1 snapshot mensuel)
  dynamic "lifecycle_rule" {
    for_each = var.sirene_prefix_delete_age_days == null ? [] : [1]

    content {
      condition {
        age            = var.sirene_prefix_delete_age_days
        matches_prefix = [var.sirene_prefix]
      }
      action {
        type = "Delete"
      }
    }
  }

  # geo : référentiel mensuel YYYY-MM/ — purge après N jours
  dynamic "lifecycle_rule" {
    for_each = var.geo_prefix_delete_age_days == null ? [] : [1]

    content {
      condition {
        age            = var.geo_prefix_delete_age_days
        matches_prefix = [var.geo_prefix]
      }
      action {
        type = "Delete"
      }
    }
  }

  # apec : partition hebdomadaire dt=YYYY-MM-DD/ — purge après N jours (default 30 = ~4 semaines)
  dynamic "lifecycle_rule" {
    for_each = var.apec_prefix_delete_age_days == null ? [] : [1]

    content {
      condition {
        age            = var.apec_prefix_delete_age_days
        matches_prefix = [var.apec_prefix]
      }
      action {
        type = "Delete"
      }
    }
  }

  # jooble : partition hebdomadaire dt=YYYY-MM-DD/offres.parquet — purge après N jours
  dynamic "lifecycle_rule" {
    for_each = var.jooble_prefix_delete_age_days == null ? [] : [1]

    content {
      condition {
        age            = var.jooble_prefix_delete_age_days
        matches_prefix = [var.jooble_prefix]
      }
      action {
        type = "Delete"
      }
    }
  }

  # Versions non-courantes (ARCHIVED) — garder uniquement la version courante (latest only).
  # num_newer_versions = 1 → supprimer toute version ARCHIVED dès qu'il existe 1 version plus récente.
  # Exemple : run1(v1) → run2(v2, v1=archivée supprimée immédiatement)
  # Utile en test quand l'ingestion tourne plusieurs fois le même jour sur le même chemin GCS.
  dynamic "lifecycle_rule" {
    for_each = var.versioning_enabled ? [1] : []

    content {
      condition {
        with_state         = "ARCHIVED"
        num_newer_versions = 1
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

# Requis pour que dbt puisse lire les données via les BigQuery external tables :
# BQ lit directement GCS au moment de la query, le SA dbt doit donc avoir accès au bucket.
resource "google_storage_bucket_iam_member" "dbt_object_viewer" {
  count = var.dbt_sa_email == "" ? 0 : 1

  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.dbt_sa_email}"
}
