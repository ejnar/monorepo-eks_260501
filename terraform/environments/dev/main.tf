# ============================================================
#  monorepo — dev environment
#  terraform/environments/dev/main.tf
#
#  Apply order:
#    Pass 1 (infra):  terraform apply -target=module.networking
#                                     -target=module.eks
#                                     -target=module.secrets
#                                     -target=helm_release.aws_lb_controller
#    Pass 2 (apps):   terraform apply
# ============================================================

terraform {
  required_version = ">= 1.10.0" # 1.10+ required for S3-native use_lockfile

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket       = "monorepo-eks-260501-tfstate-bucket-dev"
    key          = "monorepo/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # S3-native locking — no DynamoDB table needed (TF >= 1.10)
    encrypt      = true
  }
}

# ── Providers ────────────────────────────────────────────────

# aws provider must be explicit — never rely on ambient env vars in CI
provider "aws" {
  region  = var.aws_region
  profile = "admin-us"
  default_tags {
    tags = local.common_tags
  }
}

# kubernetes + helm resolve cluster_endpoint at plan time,
# so they depend on EKS being fully created first.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# ── Locals ───────────────────────────────────────────────────

locals {
  env  = "dev"
  name = "monorepo-${local.env}"

  common_tags = {
    Environment = local.env
    Project     = "monorepo"
    ManagedBy   = "terraform"
  }
}

# ── Pass 1 — Infrastructure ──────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  name               = local.name
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
  cluster_name       = local.name
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.name
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  node_desired_size  = 2
  node_min_size      = 1
  node_max_size      = 3
  tags               = local.common_tags
}

module "secrets" {
  source = "../../modules/secrets"

  name              = local.name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.common_tags
}

# AWS Load Balancer Controller — needs IRSA so it can create ALBs in AWS.
# The IAM role for the controller's service account comes from the secrets module.
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"
  timeout    = 600 # node pool scaling can push past the 5-min default

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  # Create the Kubernetes ServiceAccount and attach the IRSA annotation so
  # the controller pod can assume the IAM role and manage ALBs.
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.secrets.alb_controller_irsa_role_arn
  }

  # region is required when the controller cannot auto-detect it (common in CI)
  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.networking.vpc_id
  }

  depends_on = [module.eks]
}

# ── Pass 2 — Applications ────────────────────────────────────

# ArgoCD — GitOps controller. Watches helm/ in the repo and
# auto-syncs whenever a new image tag is committed by CI.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "6.7.14"
  timeout          = 900 # ArgoCD takes several minutes to become healthy

  values = [file("${path.module}/argocd-values.yaml")]

  depends_on = [module.eks]
}

# Metrics Server — required for HPA (cpu/memory autoscaling).
# Without this, HPA reports "unable to fetch metrics from resource metrics API".
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"
  timeout    = 300

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls" # required on EKS managed nodes
  }

  depends_on = [module.eks]
}

# service-a — Spring Boot REST API.
# image.tag is always an immutable SHA (never "latest") set by CI.
resource "helm_release" "service_a" {
  name      = "service-a"
  namespace = "default"
  chart     = var.helm_chart_base_url != "" ? "${var.helm_chart_base_url}/service-a" : "${path.module}/../../../helm/service-a"
  timeout   = 600  # 10 min — image pull + Spring Boot startup
  atomic    = true # auto-rollback so Terraform state stays clean
  wait      = true

  set {
    name  = "image.repository"
    value = "ghcr.io/${var.github_org}/service-a"
  }

  set {
    name  = "image.tag"
    value = var.service_a_image_tag # required — no default; CI must always pass this
  }

  # Wire the pod's service account to the IRSA role so it can read from
  # Secrets Manager without any static credentials in the pod environment.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.secrets.service_a_irsa_role_arn
  }

  set {
    name  = "env.AWS_REGION"
    value = var.aws_region
  }

  set {
    name  = "env.AWS_SECRETS_ENABLED"
    value = "true"
  }

  depends_on = [module.eks, helm_release.aws_lb_controller]
}

# service-b — Spring Boot WebFlux reactive API.
resource "helm_release" "service_b" {
  name      = "service-b"
  namespace = "default"
  chart     = var.helm_chart_base_url != "" ? "${var.helm_chart_base_url}/service-b" : "${path.module}/../../../helm/service-b"
  timeout   = 600
  atomic    = true
  wait      = true

  set {
    name  = "image.repository"
    value = "ghcr.io/${var.github_org}/service-b"
  }

  set {
    name  = "image.tag"
    value = var.service_b_image_tag # required — no default
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.secrets.service_b_irsa_role_arn
  }

  set {
    name  = "env.AWS_REGION"
    value = var.aws_region
  }

  set {
    name  = "env.AWS_SECRETS_ENABLED"
    value = "true"
  }

  depends_on = [module.eks, helm_release.aws_lb_controller]
}

# Ingress — ALB with HTTPS, HTTP→HTTPS redirect, path-based routing.
# ACM certificate must already be validated before apply.
resource "helm_release" "ingress" {
  name      = "app-ingress"
  namespace = "default"
  chart     = var.helm_chart_base_url != "" ? "${var.helm_chart_base_url}/ingress" : "${path.module}/../../../helm/ingress"
  timeout   = 600

  set {
    name  = "domain"
    value = var.domain_name
  }

  set {
    name  = "acmCertArn"
    value = var.acm_certificate_arn
  }

  depends_on = [
    helm_release.service_a,
    helm_release.service_b,
    helm_release.aws_lb_controller,
  ]
}
