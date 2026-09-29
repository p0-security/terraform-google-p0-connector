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
    cloudsql = "sha-49c310f@sha256:cdcbcbd778fbc752cc3144fff665f569f0d56bfb4b4e104e9d88a0b33b37f5c9"
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

# Lets the connector list and create IAM database users. One role per
# connector so several VPCs in a project don't collide; role IDs can't
# contain hyphens.
resource "google_project_iam_custom_role" "connector" {
  project     = var.project_id
  role_id     = replace(var.connector_service_account_name, "-", "_")
  title       = "P0 CloudSQL connector"
  description = "Lets the P0 CloudSQL connector in VPC ${var.vpc_network} create IAM database users"
  permissions = [
    "cloudsql.instances.get",
    "cloudsql.users.create",
    "cloudsql.users.list",
    "resourcemanager.projects.get",
  ]
}

resource "google_project_iam_member" "connector_role" {
  project = var.project_id
  role    = google_project_iam_custom_role.connector.name
  member  = "serviceAccount:${google_service_account.connector.email}"
}

# Lets the connector log in to the instance as an IAM database user.
resource "google_project_iam_member" "connector_instance_user" {
  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = "serviceAccount:${google_service_account.connector.email}"
}
