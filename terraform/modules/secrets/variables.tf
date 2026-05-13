# ============================================================
#  terraform/modules/secrets/variables.tf
# ============================================================

variable "name" {
  type        = string
  description = "Name prefix applied to all resources (e.g. monorepo-dev)"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the EKS cluster OIDC provider (from module.eks.oidc_provider_arn)"
}

variable "oidc_provider_url" {
  type        = string
  description = "URL of the EKS cluster OIDC provider (from module.eks.oidc_provider_url)"
}

variable "app_secret_key_value" {
  type        = string
  sensitive   = true
  description = "Secret value stored in Secrets Manager for service-a"
  default     = "change-me-before-production-1"
}

variable "notification_api_key_value" {
  type        = string
  sensitive   = true
  description = "Secret value stored in Secrets Manager for service-b"
  default     = "change-me-before-production-1"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources in this module"
  default     = {}
}
