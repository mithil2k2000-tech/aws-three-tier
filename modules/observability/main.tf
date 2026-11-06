data "aws_region" "current" {}

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarms = {
    alb-5xx = {
      description = "Target 5xx responses (application errors)"
      namespace   = "AWS/ApplicationELB"
      metric      = "HTTPCode_Target_5XX_Count"
      stat        = "Sum"
      threshold   = 5
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
    unhealthy-targets = {
      description = "At least one API task failing health checks"
      namespace   = "AWS/ApplicationELB"
      metric      = "UnHealthyHostCount"
      stat        = "Maximum"
      threshold   = 0
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
    }
    ecs-cpu = {
      description = "API service CPU above 80%"
      namespace   = "AWS/ECS"
      metric      = "CPUUtilization"
      stat        = "Average"
      threshold   = 80
      dimensions  = { ClusterName = var.cluster_name, ServiceName = var.service_name }
    }
    ecs-memory = {
      description = "API service memory above 80%"
      namespace   = "AWS/ECS"
      metric      = "MemoryUtilization"
      stat        = "Average"
      threshold   = 80
      dimensions  = { ClusterName = var.cluster_name, ServiceName = var.service_name }
    }
    rds-cpu = {
      description = "Database CPU above 80%"
      namespace   = "AWS/RDS"
      metric      = "CPUUtilization"
      stat        = "Average"
      threshold   = 80
      dimensions  = { DBInstanceIdentifier = var.db_instance_id }
    }
    rds-connections = {
      description = "Database connections above 60 (db.t4g.micro max is about 80)"
      namespace   = "AWS/RDS"
      metric      = "DatabaseConnections"
      stat        = "Maximum"
      threshold   = 60
      dimensions  = { DBInstanceIdentifier = var.db_instance_id }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.stat
  dimensions          = each.value.dimensions
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name}-latency-p95"
  alarm_description   = "p95 target response time above ${var.p95_latency_threshold_s}s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.p95_latency_threshold_s
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name}-rds-free-storage"
  alarm_description   = "Database free storage below 2 GiB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  period              = 300
  evaluation_periods  = 2
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Application errors counted from structured logs.
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.name}-app-errors"
  log_group_name = var.log_group_name
  pattern        = "{ $.level = \"ERROR\" }"
  metric_transformation {
    name      = "AppErrors"
    namespace = "ThreeTier/${var.name}"
    value     = "1"
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = {
        title = "Requests and errors", region = data.aws_region.current.region, stat = "Sum", period = 60,
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
          [".", "HTTPCode_Target_5XX_Count", ".", "."],
          [".", "HTTPCode_Target_4XX_Count", ".", "."],
        ]
      } },
      { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = {
        title = "Latency (p50 / p95 / p99)", region = data.aws_region.current.region, period = 60,
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
          ["...", { stat = "p95" }],
          ["...", { stat = "p99" }],
        ]
      } },
      { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = {
        title = "ECS service", region = data.aws_region.current.region, stat = "Average", period = 60,
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
          [".", "MemoryUtilization", ".", ".", ".", "."],
        ]
      } },
      { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = {
        title = "RDS", region = data.aws_region.current.region, stat = "Average", period = 60,
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id],
          [".", "DatabaseConnections", ".", "."],
        ]
      } },
      { type = "alarm", x = 0, y = 12, width = 24, height = 4, properties = {
        title  = "Alarms"
        alarms = concat([for a in aws_cloudwatch_metric_alarm.this : a.arn], [aws_cloudwatch_metric_alarm.latency_p95.arn, aws_cloudwatch_metric_alarm.rds_storage.arn])
      } },
    ]
  })
}

resource "aws_guardduty_detector" "this" {
  #checkov:skip=CKV2_AWS_3:Single-account project, no AWS Organizations
  count                        = var.enable_guardduty ? 1 : 0
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.name}-guardduty-findings"
  description = "GuardDuty findings of severity 4 (medium) or higher"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 4] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty" {
  count = var.enable_guardduty ? 1 : 0
  rule  = aws_cloudwatch_event_rule.guardduty[0].name
  arn   = aws_sns_topic.alerts.arn
}

data "aws_iam_policy_document" "sns" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns.json
}

resource "aws_budgets_budget" "monthly" {
  count        = var.monthly_budget_usd > 0 ? 1 : 0
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
