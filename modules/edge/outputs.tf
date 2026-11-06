output "url" { value = "https://${length(var.aliases) > 0 ? var.aliases[0] : aws_cloudfront_distribution.this.domain_name}" }
output "distribution_id" { value = aws_cloudfront_distribution.this.id }
output "site_bucket" { value = aws_s3_bucket.site.id }
