variable "name" { type = string }
variable "alb_arn" { type = string }
variable "alb_dns_name" { type = string }
variable "aliases" {
  description = "Optional custom domain names. Leave empty to use the free *.cloudfront.net HTTPS endpoint."
  type        = list(string)
  default     = []
}
variable "acm_certificate_arn" {
  description = "ACM certificate in us-east-1 covering var.aliases. Required only when aliases are set."
  type        = string
  default     = null
}
variable "enable_waf" {
  description = "AWS WAF with managed rule groups and a rate limit (about $6/month base plus requests)."
  type        = bool
  default     = false
}
variable "rate_limit_per_5min" {
  type    = number
  default = 1000
}
