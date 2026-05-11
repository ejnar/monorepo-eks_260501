# ============================================================
#  terraform/modules/secrets/main.tf
#
#  Creates:
#    - Secrets Manager secrets (app-secret-key, notification-api-key)
#    - IRSA IAM role for service-a
#    - IRSA IAM role for service-b
#    - IRSA IAM role for the AWS Load Balancer Controller   ← NEW
# ============================================================

# ── Secrets Manager ──────────────────────────────────────────

resource "aws_secretsmanager_secret" "app_secret_key" {
  name                    = "${var.name}-app-secret-key"
  description             = "App secret key for service-a"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "app_secret_key" {
  secret_id     = aws_secretsmanager_secret.app_secret_key.id
  secret_string = jsonencode({ value = var.app_secret_key_value })
}

resource "aws_secretsmanager_secret" "notification_api_key" {
  name                    = "${var.name}-notification-api-key"
  description             = "Notification API key for service-b"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "notification_api_key" {
  secret_id     = aws_secretsmanager_secret.notification_api_key.id
  secret_string = jsonencode({ value = var.notification_api_key_value })
}

# ── IAM policy: read the two secrets ─────────────────────────

data "aws_iam_policy_document" "secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      aws_secretsmanager_secret.app_secret_key.arn,
      aws_secretsmanager_secret.notification_api_key.arn,
    ]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.name}-secrets-read"
  description = "Allow reading app secrets from Secrets Manager"
  policy      = data.aws_iam_policy_document.secrets_read.json
  tags        = var.tags
}

# ── Helper: reusable OIDC assume-role document ───────────────
# Used by service-a and service-b IRSA roles.

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
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

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
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ── IRSA role: service-a ──────────────────────────────────────

resource "aws_iam_role" "service_a_irsa" {
  name               = "${var.name}-service-a-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_a_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "service_a_secrets" {
  policy_arn = aws_iam_policy.secrets_read.arn
  role       = aws_iam_role.service_a_irsa.name
}

# ── IRSA role: service-b ──────────────────────────────────────

resource "aws_iam_role" "service_b_irsa" {
  name               = "${var.name}-service-b-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_b_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "service_b_secrets" {
  policy_arn = aws_iam_policy.secrets_read.arn
  role       = aws_iam_role.service_b_irsa.name
}

# ── IRSA role: AWS Load Balancer Controller ───────────────────
#
# The ALB controller needs permissions to manage EC2 load balancers,
# target groups, security groups, and WAF rules on behalf of Ingress objects.
# AWS publishes the official managed policy document here:
#   https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller
#          /main/docs/install/iam_policy.json
#
# We create a minimal inline version covering the core permissions.
# For production, download the official policy JSON and use aws_iam_policy
# with a data "local_file" or an http data source to stay up to date.

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      # Namespace and service account name must match the values set in
      # helm_release.aws_lb_controller (kube-system / aws-load-balancer-controller)
      values = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "alb_controller_policy" {
  statement {
    sid    = "AllowLoadBalancerManagement"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:*",
      "ec2:Describe*",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyNetworkInterfaceAttribute",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCertificateDiscovery"
    effect = "Allow"
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowWAFv2"
    effect = "Allow"
    actions = [
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowShieldAndCognito"
    effect = "Allow"
    actions = [
      "shield:GetSubscriptionState",
      "cognito-idp:DescribeUserPoolClient",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowServiceLinkedRole"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.name}-alb-controller"
  description = "Permissions for the AWS Load Balancer Controller IRSA role"
  policy      = data.aws_iam_policy_document.alb_controller_policy.json
  tags        = var.tags
}

resource "aws_iam_role" "alb_controller_irsa" {
  name               = "${var.name}-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.alb_controller_irsa.name
}
