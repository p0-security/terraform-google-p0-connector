variable "project_id" {
  description = "GCP project ID in which to deploy the connector."
  type        = string
}

variable "service" {
  description = "P0 service identifier the connector brokers access to. Selects the connector image."
  type        = string
  validation {
    condition     = contains(["cloudsql"], var.service)
    error_message = "service must be cloudsql."
  }
}

variable "connector_name" {
  description = "Name for the Cloud Run service. Used as the connector's resource name (analogous to the AWS connector_arn). Must be a valid Cloud Run service name (lowercase, digits, hyphens)."
  type        = string
  default     = "p0-connector"
}

variable "region" {
  description = "Region of the subnetwork; also where the Cloud Run service is deployed."
  type        = string
}

variable "vpc_network" {
  description = "Self link or name of the VPC network the connector egresses into to reach private services (e.g. Cloud SQL PSC endpoints)."
  type        = string
}

variable "vpc_subnetwork" {
  description = "Self link or name of the subnetwork used for the connector's direct VPC egress. Must be in var.region."
  type        = string
}


variable "connector_service_account_name" {
  description = "Account ID of the service account to create for the Cloud Run service to run as"
  type        = string

  validation {
    condition     = !strcontains(var.connector_service_account_name, "@")
    error_message = "connector_service_account_name must be an account ID (e.g. \"my-connector\"), not a full service account email."
  }
}

variable "invoker_service_account_email" {
  description = "Email of the P0 service account that invokes the connector. Granted roles/run.invoker on the connector, and passed to the connector as INVOKER_SA_EMAIL"
  type        = string
}

variable "domain_allow_pattern" {
  description = "Regex pattern of email domains allowed to be granted access via the connector, e.g. \".*@example[.]com$\". Passed to the connector as DOMAIN_ALLOW_PATTERN. If null, all domains are allowed."
  type        = string
  default     = null
}

variable "image" {
  description = "Override for the connector container image. Defaults to the pinned upstream p0security image for var.service."
  type        = string
  default     = null
}

