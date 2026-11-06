data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  tags = {
    project     = "aws-three-tier"
    environment = "prod"
    owner       = var.owner
    managed-by  = "terraform"
  }
  account_id = data.aws_caller_identity.current.account_id
  # Created by the bootstrap stack; every IAM role here must carry it (the deploy role cannot create roles without it).
  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:policy/app/three-tier/three-tier-workload-boundary"
}

# One customer-managed key for logs, the database, its secret and alerts ($1/month).
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy: resource * means this key only
  #checkov:skip=CKV_AWS_111:Key policy: resource * means this key only
  #checkov:skip=CKV_AWS_356:Key policy: resource * means this key only
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${local.account_id}:*"]
    }
  }
  statement {
    sid       = "AlarmsAndEventsToEncryptedSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "${var.name} data and logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.main.key_id
}

module "network" {
  source                   = "../../modules/network"
  name                     = var.name
  nat_gateways             = var.nat_gateways
  kms_key_arn              = aws_kms_key.main.arn
  permissions_boundary_arn = local.boundary_arn
}

module "data" {
  source                   = "../../modules/data"
  name                     = var.name
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.data_subnet_ids
  app_security_group_id    = module.app.task_security_group_id
  kms_key_arn              = aws_kms_key.main.arn
  multi_az                 = var.multi_az_db
  deletion_protection      = !var.teardown_friendly
  skip_final_snapshot      = var.teardown_friendly
  permissions_boundary_arn = local.boundary_arn
}

module "app" {
  source                   = "../../modules/app"
  name                     = var.name
  vpc_id                   = module.network.vpc_id
  vpc_cidr                 = module.network.vpc_cidr
  subnet_ids               = module.network.app_subnet_ids
  kms_key_arn              = aws_kms_key.main.arn
  image                    = var.image
  desired_count            = var.desired_count
  db_host                  = module.data.endpoint
  db_name                  = module.data.db_name
  db_secret_arn            = module.data.master_secret_arn
  alb_deletion_protection  = !var.teardown_friendly
  permissions_boundary_arn = local.boundary_arn
}

module "edge" {
  source              = "../../modules/edge"
  providers           = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  name                = var.name
  alb_arn             = module.app.alb_arn
  alb_dns_name        = module.app.alb_dns_name
  enable_waf          = var.enable_waf
  aliases             = var.aliases
  acm_certificate_arn = var.acm_certificate_arn
}

module "observability" {
  source                  = "../../modules/observability"
  name                    = var.name
  kms_key_arn             = aws_kms_key.main.arn
  alert_email             = var.alert_email
  alb_arn_suffix          = module.app.alb_arn_suffix
  target_group_arn_suffix = module.app.target_group_arn_suffix
  cluster_name            = module.app.cluster_name
  service_name            = module.app.service_name
  db_instance_id          = module.data.instance_id
  log_group_name          = module.app.log_group_name
  enable_guardduty        = var.enable_guardduty
  monthly_budget_usd      = var.monthly_budget_usd
}
