# Stack 1 - things the other stacks need first:
#   * 3 ECR repositories for the Java images
#   * the NAME of the S3 artefact bucket (the bucket itself is created by 01-bootstrap.sh)
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = { Project = "yawar-cloud-patterns" } }
}

variable "region" { default = "us-east-1" }

data "aws_caller_identity" "me" {}

resource "aws_ecr_repository" "svc" {
  for_each     = toset(["ms-donors", "ms-inventory", "ms-requests"])
  name         = "yawar/${each.key}"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}

# The S3 artefact bucket is created by scripts/aws/01-bootstrap.sh with the AWS CLI, not here:
# the AWS provider reads the bucket's Object Lock configuration after creating it, and AWS Academy
# accounts deny s3:GetBucketObjectLockConfiguration through a service control policy.
locals {
  artifact_bucket = "yawar-artifacts-${data.aws_caller_identity.me.account_id}"
}

output "ecr_registry"     { value = "${data.aws_caller_identity.me.account_id}.dkr.ecr.${var.region}.amazonaws.com" }
output "ecr_repositories" { value = { for k, r in aws_ecr_repository.svc : k => r.repository_url } }
output "artifact_bucket"  { value = local.artifact_bucket }
