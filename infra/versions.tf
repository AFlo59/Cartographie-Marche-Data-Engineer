terraform {
  required_version = ">= 1.6.0"

  # Backend GCS : stocke le state Terraform dans GCP
  # À créer UNE FOIS dans Cloud Shell avant le premier terraform init :
  #   gcloud storage buckets create gs://datatalent-tfstate-cartographie-data-engineer \
  #     --location=europe-west1 --project=cartographie-data-engineer
  # Puis migrer le state local une fois :
  #   docker compose run --rm infra-iac terraform-oauth init -migrate-state
  backend "gcs" {
    bucket = "datatalent-tfstate-cartographie-data-engineer"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
