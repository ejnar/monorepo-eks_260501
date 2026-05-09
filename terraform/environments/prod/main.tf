terraform {
  required_version = ">= 1.7.0"

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
    bucket         = "your-tfstate-bucket-prod"
    key            = "monorepo/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

locals {
  env      = "prod"
  name     = "monorepo-${local.env}"
  common_tags = {
    Environment = local.env
    Project     = "monorepo"
    ManagedBy   = "terraform"
  }
}

module "networking" {
  source             = "../../modules/networking"
  name               = local.name
  vpc_cidr           = "10.1.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  cluster_name       = local.name
  tags               = local.common_tags
}

module "eks" {
  source              = "../../modules/eks"
  cluster_name        = local.name
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  node_instance_types = ["t3.large"]
  node_desired_size   = 3
  node_min_size       = 2
  node_max_size       = 8
  tags                = local.common_tags
}

module "secrets" {
  source            = "../../modules/secrets"
  name              = local.name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.common_tags
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set { name = "clusterName"; value = module.eks.cluster_name }
  set { name = "serviceAccount.create"; value = "true" }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "6.7.14"
  values           = [file("${path.module}/argocd-values.yaml")]
  depends_on       = [module.eks]
}

resource "helm_release" "service_a" {
  name      = "service-a"
  chart     = "${path.root}/../../../../helm/service-a"
  namespace = "default"
  set { name = "image.tag"; value = var.service_a_image_tag }
  set { name = "replicaCount"; value = "3" }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.secrets.service_a_irsa_role_arn
  }
  depends_on = [module.eks, helm_release.aws_lb_controller]
}

resource "helm_release" "service_b" {
  name      = "service-b"
  chart     = "${path.root}/../../../../helm/service-b"
  namespace = "default"
  set { name = "image.tag"; value = var.service_b_image_tag }
  set { name = "replicaCount"; value = "3" }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.secrets.service_b_irsa_role_arn
  }
  depends_on = [module.eks, helm_release.aws_lb_controller]
}

resource "helm_release" "ingress" {
  name      = "app-ingress"
  chart     = "${path.root}/../../../../helm/ingress"
  namespace = "default"
  set { name = "domain"; value = var.domain_name }
  set { name = "acmCertArn"; value = var.acm_certificate_arn }
  depends_on = [helm_release.service_a, helm_release.service_b]
}
