variable "project_id" {
  description = "GCP project ID in which to deploy the connector."
  type        = string
}

variable "service" {
  description = "P0 service identifier the connector brokers access to. Selects the connector image."
  type        = string
  validation {
    condition     = contains(["mysql", "pg"], var.service)
    error_message = "service must be one of: mysql, pg."
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


variable "invoker_members" {
  description = "IAM members granted roles/run.invoker on the connector, i.e. the P0 principal(s) allowed to invoke it (analogous to granting lambda:InvokeFunction to the P0 role on AWS). E.g. [\"serviceAccount:p0@example.iam.gserviceaccount.com\"]."
  type        = list(string)
  default     = []
}

variable "image" {
  description = "Override for the connector container image. Defaults to the pinned upstream p0security image for var.service."
  type        = string
  default     = null
}

