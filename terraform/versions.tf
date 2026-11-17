terraform {
  required_version = ">= 1.8.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # State lives in a DigitalOcean Spaces bucket (S3-compatible).
  # Bucket name and keys come from backend.hcl (git-ignored):
  #   tofu init -backend-config=backend.hcl
  backend "s3" {
    key    = "devops/terraform.tfstate"
    region = "us-east-1" # ignored by Spaces, required by the backend

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
