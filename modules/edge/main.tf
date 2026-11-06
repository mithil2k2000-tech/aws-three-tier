# Presentation tier: static frontend in a private S3 bucket, API via an internal ALB, both behind CloudFront.

resource "aws_s3_bucket" "site" {
  #checkov:skip=CKV2_AWS_62:No consumer for object events
  #checkov:skip=CKV_AWS_144:Single-region design; see docs/well-architected.md (reliability)
  #checkov:skip=CKV_AWS_18:Access logs for this bucket would add a second bucket for little value at this scale
  #checkov:skip=CKV_AWS_145:Public static assets; SSE-KMS with OAC needs a key policy for CloudFront and adds cost for no confidentiality gain
  bucket_prefix = "${var.name}-site-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    id     = "old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name}-site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${var.name}-alb"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

data "aws_cloudfront_cache_policy" "optimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_origin_request_policy" "all_viewer" { name = "Managed-AllViewerExceptHostHeader" }
data "aws_cloudfront_response_headers_policy" "security" { name = "Managed-SecurityHeadersPolicy" }

resource "aws_cloudfront_distribution" "this" {
  #checkov:skip=CKV_AWS_86:Standard logging needs an ACL-enabled bucket; enable CloudFront logging v2 if required
  #checkov:skip=CKV_AWS_310:Single API origin; S3 is already highly available
  #checkov:skip=CKV_AWS_374:Public demo with no geographic restriction requirement
  #checkov:skip=CKV2_AWS_47:WAF is optional; when enabled it includes AWSManagedRulesKnownBadInputsRuleSet (Log4j)
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # Europe and North America edges only: cheapest
  aliases             = var.aliases
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
  http_version        = "http2and3"

  origin {
    origin_id                = "site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id   = "api"
    domain_name = var.alb_dns_name
    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  default_cache_behavior {
    target_origin_id           = "site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = length(var.aliases) == 0
    acm_certificate_arn            = length(var.aliases) > 0 ? var.acm_certificate_arn : null
    ssl_support_method             = length(var.aliases) > 0 ? "sni-only" : null
    minimum_protocol_version       = length(var.aliases) > 0 ? "TLSv1.2_2021" : "TLSv1"
  }
}

data "aws_iam_policy_document" "site" {
  statement {
    sid       = "CloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
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

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.site.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------- Optional WAF (CloudFront scope lives in us-east-1) ----------------
resource "aws_wafv2_web_acl" "this" {
  #checkov:skip=CKV_AWS_192:Log4j covered by AWSManagedRulesKnownBadInputsRuleSet in the dynamic rule block
  #checkov:skip=CKV2_AWS_31:WAF logging adds cost; enable with a Firehose or log group when WAF is used in production
  count    = var.enable_waf ? 1 : 0
  provider = aws.us_east_1
  name     = var.name
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 0
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = { 1 = "AWSManagedRulesCommonRuleSet", 2 = "AWSManagedRulesKnownBadInputsRuleSet", 3 = "AWSManagedRulesSQLiRuleSet" }
    content {
      name     = rule.value
      priority = rule.key
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}
