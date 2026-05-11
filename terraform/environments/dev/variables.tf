# ============================================================
#  monorepo — dev environment
#  terraform/environments/dev/variables.tf
# ============================================================

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "domain_name" {
  type        = string
  description = "Public domain for the ALB ingress (e.g. dev.example.com)"
  default     = "dev.songpoint.net"
}

variable "acm_certificate_arn" {
  type        = string
  description = "ARN of a validated ACM certificate covering var.domain_name"
  # No default — must be supplied; certificate must already be DNS-validated.
}

variable "github_org" {
  type        = string
  description = "GitHub organisation name used to build the GHCR image path"
  default     = "ejnar"
}

# No default — CI always passes an immutable SHA tag (e.g. git rev-parse --short HEAD).
# Leaving this unset causes terraform plan to fail loudly rather than silently pull 'latest'.
variable "service_a_image_tag" {
  type        = string
  description = "Immutable Docker image tag for service-a (git SHA from CI)"
}

variable "service_b_image_tag" {
  type        = string
  description = "Immutable Docker image tag for service-b (git SHA from CI)"
}

variable "helm_chart_base_url" {
  type        = string
  description = <<-EOT
    Optional OCI or HTTP Helm repo base URL for service charts.
    When set, charts are pulled from the registry instead of the local path:
      oci://ghcr.io/your-org/helm-charts
    When empty (default), falls back to relative local path — suitable for
    local development but may break in CI. Publish charts to a registry for
    production use.
  EOT
  default     = ""
}
