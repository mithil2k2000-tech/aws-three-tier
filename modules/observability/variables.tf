variable "name" { type = string }
variable "kms_key_arn" { type = string }
variable "alert_email" { type = string }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "cluster_name" { type = string }
variable "service_name" { type = string }
variable "db_instance_id" { type = string }
variable "log_group_name" { type = string }
variable "p95_latency_threshold_s" {
  type    = number
  default = 1
}
variable "enable_guardduty" {
  description = "GuardDuty has a 30-day free trial, then costs depend on usage. Skip if your account already has a detector."
  type        = bool
  default     = true
}
variable "monthly_budget_usd" {
  description = "Set 0 to skip, e.g. if the account already has a budget."
  type        = number
  default     = 30
}
