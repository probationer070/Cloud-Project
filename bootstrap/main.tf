########################################################
# Bootstrap: Terraform remote state backend
# Creates the S3 state bucket that backs every project's
# remote state. Locking is handled by native S3 lockfiles
# (use_lockfile in each backend.tf) — no DynamoDB needed.
#
# Chicken-and-egg: this infra CANNOT live in a config that
# uses it as a backend, so this config keeps its OWN LOCAL
# state. Apply once; it changes rarely.
#
# Fixes ERR-001 (local state not shared across machines).
########################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

########################################################
# GitHub Actions OIDC — lets CI assume this role without
# storing long-lived AWS credentials in GitHub secrets.
########################################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-oidc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:probationer070/Cloud-Project:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-plan-read"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
      },
      {
        Sid    = "ReadOnly"
        Effect = "Allow"
        Action = [
          "iam:Get*", "iam:List*",
          "lambda:Get*", "lambda:List*",
          "s3:Get*", "s3:List*",
          "dynamodb:Describe*", "dynamodb:List*",
          "cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*",
          "logs:Describe*", "logs:Get*", "logs:List*",
          "ssm:Describe*", "ssm:Get*", "ssm:List*",
          "apigateway:GET",
          "bedrock:Get*", "bedrock:List*",
          "ec2:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}

########################################################
# S3 — remote state storage (shared across P1–P4)
########################################################

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
  tags   = var.common_tags

  # Allow `terraform destroy` to purge all object versions + delete-markers.
  # Without this, DeleteBucket fails 409 BucketNotEmpty on a versioned bucket.
  force_destroy = true
}

# Versioning: keep state history so a bad write can be rolled back
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny any non-TLS access to the state bucket (defense-in-depth)
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.tfstate.arn,
        "${aws_s3_bucket.tfstate.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
