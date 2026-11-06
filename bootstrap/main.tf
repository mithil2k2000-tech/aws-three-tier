# One-time stack, applied by a human administrator with local state, then migrated into the bucket it creates.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = { project = "aws-three-tier", managed-by = "terraform", stack = "bootstrap" } }
}

variable "region" {
  type    = string
  default = "eu-west-2"
}
variable "github_repo" {
  description = "owner/repo"
  type        = string
}
variable "github_subject_prefix" {
  description = "OIDC subject prefix. Defaults to repo:<owner/repo>. Some accounts need the ID-qualified form, e.g. repo:owner@123/repo@456."
  type        = string
  default     = ""
}
variable "create_oidc_provider" {
  description = "false if the account already has token.actions.githubusercontent.com (only one is allowed)."
  type        = bool
  default     = true
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  p       = data.aws_partition.current.partition
  subject = var.github_subject_prefix != "" ? var.github_subject_prefix : "repo:${var.github_repo}"
  path    = "/app/three-tier/"
}

# ---------------- Terraform state ----------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV2_AWS_62:No consumer for object events
  #checkov:skip=CKV_AWS_144:Single-region design; see docs/well-architected.md (reliability)
  #checkov:skip=CKV_AWS_18:Access logs for this bucket would add a second bucket for little value at this scale
  #checkov:skip=CKV_AWS_145:SSE-S3 plus TLS-only policy, versioning and IAM-restricted access; CMK adds cost
  bucket = "three-tier-tfstate-${local.account}"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json
}

# ---------------- Container registry ----------------
resource "aws_ecr_repository" "api" {
  #checkov:skip=CKV_AWS_136:AES256 at rest; images contain no secrets
  name                 = "three-tier-api"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({ rules = [{
    rulePriority = 1, description = "keep the last 20 images"
    selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
    action       = { type = "expire" }
  }] })
}

# ---------------- GitHub OIDC ----------------
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
  for_each = { plan = ["${local.subject}:pull_request", "${local.subject}:environment:prod-plan"], deploy = ["${local.subject}:environment:prod"] }
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# ---------------- Permissions boundary for every role the app stack creates ----------------
data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_108:Permissions boundary is a ceiling, not a grant; roles get narrower inline policies
  #checkov:skip=CKV_AWS_111:Permissions boundary is a ceiling, not a grant
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken and ec2:Describe* do not support resource scoping
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
    resources = ["arn:${local.p}:logs:*:${local.account}:*"]
  }
  statement {
    sid       = "SecretsAndKeys"
    actions   = ["secretsmanager:GetSecretValue", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["arn:${local.p}:secretsmanager:*:${local.account}:secret:*", "arn:${local.p}:kms:*:${local.account}:key/*"]
  }
  statement {
    sid       = "PullImages"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = ["arn:${local.p}:ecr:*:${local.account}:repository/*"]
  }
  statement {
    sid       = "Unscopable"
    actions   = ["ecr:GetAuthorizationToken", "cloudwatch:PutMetricData", "ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name   = "three-tier-workload-boundary"
  path   = local.path
  policy = data.aws_iam_policy_document.boundary.json
}

# ---------------- Plan role: read-only plus state ----------------
resource "aws_iam_role" "plan" {
  name               = "three-tier-github-plan"
  assume_role_policy = data.aws_iam_policy_document.trust["plan"].json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.p}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_rw" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/three-tier/*"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_rw.json
}

# ---------------- Deploy role: everything except unbounded IAM ----------------
resource "aws_iam_role" "deploy" {
  name                 = "three-tier-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.trust["deploy"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "deploy_poweruser" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:${local.p}:iam::aws:policy/PowerUserAccess" # no IAM, Organizations or account management
}

data "aws_iam_policy_document" "deploy_iam" {
  #checkov:skip=CKV_AWS_356:Only read-only iam:Get*/List* and condition-limited CreateServiceLinkedRole use *
  statement {
    sid       = "CreateOnlyBoundedRolesInAppPath"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:AttachRolePolicy"]
    resources = ["arn:${local.p}:iam::${local.account}:role${local.path}*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }
  statement {
    sid = "ManageAppPathRoles"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRoleTags",
    ]
    resources = ["arn:${local.p}:iam::${local.account}:role${local.path}*"]
  }
  statement {
    sid       = "PassAppRolesToServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.p}:iam::${local.account}:role${local.path}*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "vpc-flow-logs.amazonaws.com", "monitoring.rds.amazonaws.com"]
    }
  }
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com", "ecs.application-autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com", "guardduty.amazonaws.com", "malware-protection.guardduty.amazonaws.com",
        "vpcorigin.cloudfront.amazonaws.com",
      ]
    }
  }
  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid       = "ProtectBoundaryAndDeployRole"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:SetDefaultPolicyVersion"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy_iam" {
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_iam.json
}

resource "aws_iam_role_policy" "deploy_state" {
  role   = aws_iam_role.deploy.id
  name   = "state"
  policy = data.aws_iam_policy_document.state_rw.json
}

output "state_bucket" { value = aws_s3_bucket.state.id }
output "ecr_repository_url" { value = aws_ecr_repository.api.repository_url }
output "plan_role_arn" { value = aws_iam_role.plan.arn }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "boundary_policy_arn" { value = aws_iam_policy.boundary.arn }
