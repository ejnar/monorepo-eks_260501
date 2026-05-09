terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }


}

provider "aws" {
  profile = "admin-us"
  region  = "us-east-1"
}

resource "aws_s3_bucket" "demo" {
  bucket = "monorepo-unique-demo-bucket-7890123"

  tags = {
    Name = "Terraform Demo"
  }
}