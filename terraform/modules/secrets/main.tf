resource "aws_secretsmanager_secret" "app_secret_key" {
  name                    = "app-secret-key"
  description             = "Application secret key for service-a"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "app_secret_key" {
  secret_id     = aws_secretsmanager_secret.app_secret_key.id
  secret_string = jsonencode({ value = var.app_secret_key_value })
}

resource "aws_secretsmanager_secret" "notification_api_key" {
  name                    = "notification-api-key"
  description             = "Notification API key for service-b"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "notification_api_key" {
  secret_id     = aws_secretsmanager_secret.notification_api_key.id
  secret_string = jsonencode({ value = var.notification_api_key_value })
}

# IAM policy allowing EKS service accounts to read these secrets (IRSA)
data "aws_iam_policy_document" "secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      aws_secretsmanager_secret.app_secret_key.arn,
      aws_secretsmanager_secret.notification_api_key.arn,
    ]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.name}-secrets-read-policy"
  description = "Allow reading app secrets from Secrets Manager"
  policy      = data.aws_iam_policy_document.secrets_read.json
  tags        = var.tags
}

# IRSA role for service-a
data "aws_iam_policy_document" "service_a_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:service-a-sa"]
    }
  }
}

resource "aws_iam_role" "service_a_irsa" {
  name               = "${var.name}-service-a-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_a_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "service_a_secrets" {
  policy_arn = aws_iam_policy.secrets_read.arn
  role       = aws_iam_role.service_a_irsa.name
}

# IRSA role for service-b
data "aws_iam_policy_document" "service_b_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:service-b-sa"]
    }
  }
}

resource "aws_iam_role" "service_b_irsa" {
  name               = "${var.name}-service-b-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_b_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "service_b_secrets" {
  policy_arn = aws_iam_policy.secrets_read.arn
  role       = aws_iam_role.service_b_irsa.name
}
