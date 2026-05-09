variable "name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "app_secret_key_value" {
  type      = string
  sensitive = true
  default   = "change-me-in-production"
}

variable "notification_api_key_value" {
  type      = string
  sensitive = true
  default   = "change-me-in-production"
}

variable "tags" {
  type    = map(string)
  default = {}
}
