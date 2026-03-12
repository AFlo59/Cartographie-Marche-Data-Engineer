terraform {
  required_version = ">= 1.6.0"

  # Backend GCS : stocke le state Terraform dans GCP
  # Le bucket est configuré dynamiquement via -backend-config lors du terraform init
  # dans le workflow CI/CD (voir .github/workflows/infra-deploy.yml)
  backend "gcs" {
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
