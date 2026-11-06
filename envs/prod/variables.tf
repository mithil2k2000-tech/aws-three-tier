variable "region" {
  type    = string
  default = "eu-west-2"
}
variable "name" {
  type    = string
  default = "three-tier-prod"
}
variable "owner" { type = string }
variable "alert_email" { type = string }
variable "image" {
  description = "API image URI with immutable tag (set by the deploy workflow)."
  type        = string
}
variable "nat_gateways" {
  type    = number
  default = 1
}
variable "multi_az_db" {
  type    = bool
  default = false
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "enable_waf" {
  type    = bool
  default = false
}
variable "enable_guardduty" {
  type    = bool
  default = true
}
variable "monthly_budget_usd" {
  type    = number
  default = 30
}
variable "teardown_friendly" {
  description = "true = no deletion protection and no final snapshot, so 'destroy' works in one go. Use for demos only."
  type        = bool
  default     = false
}
variable "aliases" {
  type    = list(string)
  default = []
}
variable "acm_certificate_arn" {
  type    = string
  default = null
}
