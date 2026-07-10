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
    cloudsql = "sha-9af81d5@sha256:7d35020bc04c9aa9781a225a803bf22d606ba9a96d5854a3f5490d65d4418c0f"
  }

  image = coalesce(
    var.image,
    "docker.io/p0security/p0-connector-${var.service}:${local.service_image_digests[var.service]}",
  )
}

# Service account the connector runs as. Grant this access to the connected
# service (e.g. as a Cloud SQL IAM user) via the service_account_email output.
resource "google_service_account" "connector" {
  project      = var.project_id
  account_id   = var.connector_service_account_name
  display_name = "P0 Cloud Run ${var.service} connector"
  description  = "Service account used by the P0 Cloud Run connector for CloudSQL in VPC ${var.vpc_network}"
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
  ingress     = "INGRESS_TRAFFIC_ALL"
  description = "P0 Cloud Run connector for CloudSQL in VPC ${var.vpc_network}"

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