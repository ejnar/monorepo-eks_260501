variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "domain_name" {
  type    = string
  default = "app.yourdomain.com"
}

variable "acm_certificate_arn" {
  type = string
}

variable "service_a_image_tag" {
  type    = string
  default = "latest"
}

variable "service_b_image_tag" {
  type    = string
  default = "latest"
}
