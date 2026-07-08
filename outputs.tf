output "service_name" {
  description = "Name of the Cloud Run connector service."
  value       = google_cloud_run_v2_service.connector.name
}

output "service_id" {
  description = "Full resource ID of the Cloud Run connector service (for downstream IAM bindings or references)."
  value       = google_cloud_run_v2_service.connector.id
}

output "service_uri" {
  description = "HTTPS URL P0 invokes the connector at (requires an IAM identity token)."
  value       = google_cloud_run_v2_service.connector.uri
}

output "service_account_email" {
  description = "Email of the service account the connector runs as. Grant this access to the connected service (e.g. as a Cloud SQL IAM user)."
  value       = google_service_account.connector.email
}

output "service_account_member" {
  description = "IAM member string (serviceAccount:<email>) for the connector's service account, for use in IAM bindings."
  value       = "serviceAccount:${google_service_account.connector.email}"
}
