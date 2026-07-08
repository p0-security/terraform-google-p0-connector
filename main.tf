terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}


locals {
  service_image_digests = {
    mysql = "sha-76229bf@sha256:42c508c6c3b6d26cd9a07714fd7cc0d08a2e720b87d31d1469cb42854ab698b5"
    pg    = "sha-76229bf@sha256:33e8ae960546c4c23c8e5abe2af829c6f46774b5ded4ba92c57e12e821a4bb64"
  }

  image = coalesce(
    var.image,
    "docker.io/p0security/p0-connector-${var.service}-gcloud:${local.service_image_digests[var.service]}",
  )
}

# Service account the connector runs as. Grant this access to the connected
# service (e.g. as a Cloud SQL IAM user) via the service_account_email output.
resource "google_service_account" "connector" {
  project      = var.project_id
  account_id   = var.connector_name
  display_name = "P0 Cloud Run ${var.service} connector"
}

resource "google_cloud_run_v2_service" "connector" {
  project             = var.project_id
  name                = var.connector_name
  location            = var.region
  deletion_protection = false
  # This sets what CIDR is allowed to hit the connector from the internet, which
  # we're "disabling" by allowing all traffic.
  # P0 invokes the connector over HTTPS from outside GCP; access is gated by IAM
  # (roles/run.invoker), not by ingress restrictions.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.connector.email

    containers {
      image = local.image

      # Checked by the connector against the caller's OIDC token on every
      # request, in addition to the roles/run.invoker IAM grant below.
      env {
        name  = "INVOKER_SA_EMAIL"
        value = var.invoker_service_account_email
      }

      dynamic "env" {
        for_each = var.domain_allow_pattern == null ? [] : [var.domain_allow_pattern]
        content {
          name  = "DOMAIN_ALLOW_PATTERN"
          value = env.value
        }
      }
    }

    # Direct VPC egress into the single consumer VPC so the connector can reach
    # private services (e.g. Cloud SQL PSC endpoints) on internal IPs.
    vpc_access {
      # 10.0.0.0/24, 172.16.0.0/20, and 192.168.0.0/16 go out to the VPC. All
      # other traffic goes out to the internet as usual.
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.vpc_network
        subnetwork = var.vpc_subnetwork
      }
    }
  }
}

# Grant the P0 principal permission to invoke the connector.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.connector.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.invoker_service_account_email}"
}