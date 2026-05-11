# ============================================================
#  terraform/modules/secrets/outputs.tf
# ============================================================

output "service_a_irsa_role_arn" {
  description = "ARN of the IRSA role for service-a pods"
  value       = aws_iam_role.service_a_irsa.arn
}

output "service_b_irsa_role_arn" {
  description = "ARN of the IRSA role for service-b pods"
  value       = aws_iam_role.service_b_irsa.arn
}

# This is the output referenced in main.tf:
#   module.secrets.alb_controller_irsa_role_arn
output "alb_controller_irsa_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller_irsa.arn
}

output "app_secret_arn" {
  description = "ARN of the app-secret-key secret in Secrets Manager"
  value       = aws_secretsmanager_secret.app_secret_key.arn
}

output "notification_api_key_arn" {
  description = "ARN of the notification-api-key secret in Secrets Manager"
  value       = aws_secretsmanager_secret.notification_api_key.arn
}
