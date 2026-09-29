# terraform-google-p0-connector

Deploys a P0 connector as a [Cloud Run v2](https://cloud.google.com/run/docs) service in your GCP
project, for brokering just-in-time access to a Cloud SQL database.

A connector is a small, stateless P0 runtime that runs inside your own cloud account and provisions
access to your infrastructure from there. Because it runs inside your trust boundary, the
credentials it uses to reach the database stay in your environment: P0's SaaS is never granted
standing permission to issue database grants on its own, and no standing credential is handed to an
engineer's laptop. It also keeps the connector's privileges scoped to your IAM rather than requiring
you to delegate broad grant-making authority to an external service.

Running inside your VPC also lets the connector reach databases that are only available on private
IPs, which is one of the cases this module is built for: it configures direct VPC egress so the
connector can reach the instance on an internal address. For the full rationale, see
[P0 Connectors](https://docs.p0.dev/readme/connectors).

The module creates:

- a dedicated service account for the Cloud Run service to run as,
- the Cloud Run v2 service, running the pinned upstream `p0security/p0-connector-<service>` image,
  with direct VPC egress into the network and subnetwork you specify,
- a `roles/run.invoker` binding for the P0 service account that calls the connector,
- a project custom role that lets the connector list and create IAM database users, bound to the
  connector's service account along with `roles/cloudsql.instanceUser` so it can log in.

The custom role holds `cloudsql.instances.get`, `cloudsql.users.create`, `cloudsql.users.list` and
`resourcemanager.projects.get`. Its ID is `connector_service_account_name` with hyphens replaced by
underscores, so each connector in a project gets its own role.

## Requirements

| Name | Version |
| ---- | ------- |
| `hashicorp/google` | `~> 6.0` |

## Prerequisites

- A GCP project, and `google` provider credentials able to create service accounts, Cloud Run
  services, and IAM bindings in it. The credentials also need to create custom roles and set the
  project's IAM policy. The module does not enable any APIs; enable the Cloud Run, IAM, and Service
  Account Credentials APIs on the project beforehand.
- An existing VPC network and subnetwork, passed as `vpc_network` and `vpc_subnetwork`. The
  subnetwork is used for the connector's direct VPC egress and must be in `var.region`. This module
  does not create either.
- A Cloud SQL instance the connector can reach on a private IP from that subnetwork — for example
  via a Private Service Connect endpoint, or private services access. The module takes no input
  identifying the instance and creates no route to it; reachability is yours to arrange, and is
  worth confirming before you apply.
- The email of the P0 service account that will invoke the connector, passed as
  `invoker_service_account_email`. Obtain this from P0.

## Usage

```hcl
module "p0_connector" {
  source  = "p0-security/p0-connector/google"
  version = "~> 0.0.3"

  project_id = "my-project"
  service    = "cloudsql"
  region     = "us-central1"

  vpc_network    = "my-vpc"
  vpc_subnetwork = "my-subnet-us-central1"

  connector_service_account_name = "p0-connector"
  invoker_service_account_email  = "p0-invoker@p0-example.iam.gserviceaccount.com"

  # Optional
  connector_name       = "p0-connector"
  domain_allow_pattern = ".*@example[.]com$"
}

output "p0_connector_uri" {
  value = module.p0_connector.service_uri
}

output "p0_connector_service_account" {
  value = module.p0_connector.service_account_email
}
```

## After apply

Two steps are required after `terraform apply`, neither of which this module performs:

1. **Add the connector's service account as a user on each database instance.** Use the
   `service_account_email` output. The module grants the project-level roles the connector needs,
   but it takes no input naming your instances, so adding the service account as a Cloud SQL IAM
   user and granting it in-database privileges is yours to do per instance. See
   [Manage Cloud SQL users with IAM authentication](https://cloud.google.com/sql/docs/postgres/add-manage-iam-users)
   for the exact steps for your database engine.

2. **Hand the `service_uri` output back to P0.** This is the HTTPS URL P0 invokes the connector at.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | -------- |
| `project_id` | GCP project ID in which to deploy the connector. | `string` | n/a | yes |
| `service` | P0 service identifier the connector brokers access to. Selects the connector image. Must be `cloudsql`. | `string` | n/a | yes |
| `region` | Region of the subnetwork; also where the Cloud Run service is deployed. | `string` | n/a | yes |
| `vpc_network` | Self link or name of the VPC network the connector egresses into to reach private services (e.g. Cloud SQL PSC endpoints). | `string` | n/a | yes |
| `vpc_subnetwork` | Self link or name of the subnetwork used for the connector's direct VPC egress. Must be in `var.region`. | `string` | n/a | yes |
| `connector_service_account_name` | Account ID of the service account to create for the Cloud Run service to run as. Must be an account ID (e.g. `my-connector`), not a full service account email. | `string` | n/a | yes |
| `invoker_service_account_email` | Email of the P0 service account that invokes the connector. Granted `roles/run.invoker` on the connector, and passed to the connector as `INVOKER_SA_EMAIL`. | `string` | n/a | yes |
| `connector_name` | Name for the Cloud Run service. Used as the connector's resource name (analogous to the AWS `connector_arn`). Must be a valid Cloud Run service name (lowercase, digits, hyphens). | `string` | `"p0-connector"` | no |
| `domain_allow_pattern` | Regex pattern of email domains allowed to be granted access via the connector, e.g. `".*@example[.]com$"`. Passed to the connector as `DOMAIN_ALLOW_PATTERN`. If `null`, all domains are allowed. | `string` | `null` | no |
| `image` | Override for the connector container image. Defaults to the pinned upstream `p0security` image for `var.service`. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| `service_name` | Name of the Cloud Run connector service. |
| `service_id` | Full resource ID of the Cloud Run connector service (for downstream IAM bindings or references). |
| `service_uri` | HTTPS URL P0 invokes the connector at (requires an IAM identity token). |
| `service_account_email` | Email of the service account the connector runs as. Grant this access to the connected service (e.g. as a Cloud SQL IAM user). |
| `service_account_member` | IAM member string (`serviceAccount:<email>`) for the connector's service account, for use in IAM bindings. |

## How access is secured

The Cloud Run service is deployed with `ingress = "INGRESS_TRAFFIC_ALL"`. This is deliberate, and
does not mean the connector is open to the internet. P0 calls the connector over HTTPS from outside
GCP, so restricting ingress by network origin is not workable; authorization is enforced by identity
instead, in layers:

1. **IAM.** `roles/run.invoker` on the connector is granted only to
   `invoker_service_account_email`. Cloud Run rejects unauthenticated requests, and requests bearing
   an identity token for any other principal, before they reach the container.

2. **In-connector OIDC check.** The same email is passed to the container as `INVOKER_SA_EMAIL`. The
   connector verifies the caller's OIDC token against it on every request, so a request must be
   signed by that exact P0 service account even if the IAM binding were widened.

3. **Domain allow pattern.** If `domain_allow_pattern` is set, it is passed as
   `DOMAIN_ALLOW_PATTERN` and restricts which email domains the connector will grant access for.
   When unset, all domains are allowed.

Egress is scoped as well. The connector is configured for direct VPC egress into `vpc_network` /
`vpc_subnetwork` with `egress = "PRIVATE_RANGES_ONLY"`, so only traffic destined for private address
ranges is routed into your VPC; everything else leaves over the internet as usual. See
[Cloud Run VPC egress settings](https://docs.cloud.google.com/run/docs/configuring/vpc-connectors)
for the exact ranges that setting covers.

The connector runs as its own dedicated service account. Its only project permissions are the custom
role and `roles/cloudsql.instanceUser` described above; it holds no Cloud SQL admin role.
