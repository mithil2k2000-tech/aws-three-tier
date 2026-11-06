data "aws_region" "current" {}
data "aws_elb_service_account" "this" {}

# CloudFront reaches the internal ALB through a VPC origin; inbound is limited to CloudFront's origin-facing ranges.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ---------------- Security groups ----------------
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Internal ALB: HTTP from CloudFront only"
  vpc_id      = var.vpc_id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  #checkov:skip=CKV_AWS_260:Source is the CloudFront origin-facing managed prefix list, not 0.0.0.0/0
  security_group_id = aws_security_group.alb.id
  description       = "CloudFront origin-facing ranges"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To ECS tasks"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.task.id
}

resource "aws_security_group" "task" {
  name_prefix = "${var.name}-task-"
  description = "ECS tasks: from ALB only"
  vpc_id      = var.vpc_id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  description                  = "From ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "task_https" {
  security_group_id = aws_security_group.task.id
  description       = "HTTPS to AWS APIs (ECR, Secrets Manager, CloudWatch Logs) via NAT or S3 endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "task_db" {
  security_group_id = aws_security_group.task.id
  description       = "PostgreSQL inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = var.vpc_cidr
}

# ---------------- ALB access logs ----------------
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV2_AWS_62:No consumer for object events
  #checkov:skip=CKV_AWS_144:Single-region design; see docs/well-architected.md (reliability)
  #checkov:skip=CKV_AWS_18:Access logs for this bucket would add a second bucket for little value at this scale
  #checkov:skip=CKV_AWS_145:ALB log delivery supports SSE-S3 only
  bucket_prefix = "${var.name}-alb-logs-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

# ALB log delivery supports SSE-S3 only, not SSE-KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
    noncurrent_version_expiration { noncurrent_days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "ElbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]
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

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket     = aws_s3_bucket.alb_logs.id
  policy     = data.aws_iam_policy_document.alb_logs.json
  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# ---------------- Internal ALB ----------------
resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_20:No HTTPS listener to redirect to; viewers are forced to HTTPS at CloudFront; ADR-0002
  name                       = substr(var.name, 0, 32)
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.alb_deletion_protection

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }
  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "api" {
  #checkov:skip=CKV_AWS_378:HTTP inside the VPC between ALB and tasks; ADR-0002
  name_prefix          = "api-"
  port                 = 8000
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/api/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  lifecycle { create_before_destroy = true }
}

# Plain HTTP is acceptable here: the ALB is internal and only reachable from CloudFront over the AWS network
# (see ADR-0002). Viewers always use HTTPS to CloudFront.
resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Internal ALB reached only from CloudFront VPC origin; ADR-0002
  #checkov:skip=CKV_AWS_103:No TLS listener by design; ADR-0002
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    path_pattern { values = ["/api/*"] }
  }
}

# ---------------- ECS ----------------
resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_338:Retention is a variable (default 30 days) to control cost
  name              = "/ecs/${var.name}/api"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: used by ECS itself to pull the image, write logs and inject the DB secret.
resource "aws_iam_role" "execution" {
  name_prefix          = "${var.name}-exec-"
  path                 = var.iam_path
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "execution_secret" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secret.json
}

# Task role: what the application code may call. It needs no AWS APIs, so it has no policies.
resource "aws_iam_role" "task" {
  name_prefix          = "${var.name}-task-"
  path                 = var.iam_path
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # Graviton: cheaper and more energy-efficient
  }

  container_definitions = jsonencode([{
    name                   = "api"
    image                  = var.image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "10001"
    portMappings           = [{ containerPort = 8000, protocol = "tcp" }]
    linuxParameters        = { initProcessEnabled = true, capabilities = { drop = ["ALL"] } }
    mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp" }]
    environment = [
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_SSLMODE", value = "require" },
    ]
    secrets = [
      { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
    ]
    healthCheck = {
      command     = ["CMD", "python", "-c", "import urllib.request,sys;sys.exit(urllib.request.urlopen('http://127.0.0.1:8000/api/healthz').status!=200)"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 20
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "api"
      }
    }
  }])

  volume { name = "tmp" }
}

resource "aws_ecs_service" "api" {
  name                              = "api"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30
  enable_execute_command            = false
  propagate_tags                    = "SERVICE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  # A release that cannot pass health checks is rolled back automatically (see docs/game-day.md).
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle { ignore_changes = [desired_count] } # owned by autoscaling
  depends_on = [aws_lb_listener_rule.api]
}

resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.desired_count
  max_capacity       = var.max_count
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
