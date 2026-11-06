variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "app_security_group_id" { type = string }
variable "kms_key_arn" { type = string }
variable "engine_version" {
  type    = string
  default = "16"
}
variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "multi_az" {
  description = "Standby in a second AZ with automatic failover. Doubles the instance cost."
  type        = bool
  default     = false
}
variable "backup_retention_days" {
  type    = number
  default = 7
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "skip_final_snapshot" {
  type    = bool
  default = false
}
variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 disables)."
  type        = number
  default     = 60
}
variable "performance_insights" {
  type    = bool
  default = false
}
variable "iam_path" {
  type    = string
  default = "/app/three-tier/"
}
variable "permissions_boundary_arn" {
  type    = string
  default = null
}
