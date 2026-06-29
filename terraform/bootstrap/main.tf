# Bootstrap — creates the remote state backend that the root module depends on.
# Run this ONCE before `terraform init` in ../ (the root module).
# Uses a LOCAL backend because the S3 backend it creates does not yet exist.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "cavendish-analytics"
      ManagedBy = "terraform"
      Component = "tf-state-bootstrap"
    }
  }
}

variable "aws_region" {
  description = "AWS region for the state backend"
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state (must match backend.bucket in ../main.tf)"
  type        = string
  default     = "cavendish-terraform-state"
}

variable "lock_table_name" {
  description = "DynamoDB table for state locking (must match backend.dynamodb_table in ../main.tf)"
  type        = string
  default     = "cavendish-terraform-locks"
}

# ── S3 bucket for remote state ────────────────────────────────────────────────

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB table for state locking ──────────────────────────────────────────

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  description = "S3 bucket holding remote Terraform state"
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table used for state locking"
  value       = aws_dynamodb_table.locks.id
}
