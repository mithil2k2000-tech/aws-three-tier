terraform {
  required_version = ">= 1.10" # S3 native locking (use_lockfile)
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  # Values come from -backend-config (see backend.hcl.example). S3 native locking, no DynamoDB table.
  backend "s3" {
    key          = "three-tier/prod.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.tags
  }
}

# CloudFront-scoped WAF and ACM certificates must be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}
