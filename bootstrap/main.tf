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
