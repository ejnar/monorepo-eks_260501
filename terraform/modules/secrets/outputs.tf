output "service_a_irsa_role_arn" {
  value = aws_iam_role.service_a_irsa.arn
}

output "service_b_irsa_role_arn" {
  value = aws_iam_role.service_b_irsa.arn
}

output "app_secret_arn" {
  value = aws_secretsmanager_secret.app_secret_key.arn
}

output "notification_api_key_arn" {
  value = aws_secretsmanager_secret.notification_api_key.arn
}
