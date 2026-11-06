variable "name" { type = string }
variable "cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "az_count" {
  type    = number
  default = 2
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 Availability Zones."
  }
}
variable "nat_gateways" {
  description = "0 = no internet egress from private subnets, 1 = one shared NAT (cheaper, single-AZ dependency), az_count = one per AZ (resilient)."
  type        = number
  default     = 1
}
variable "flow_log_retention_days" {
  type    = number
  default = 30
}
variable "kms_key_arn" { type = string }
variable "iam_path" {
  type    = string
  default = "/app/three-tier/"
}
variable "permissions_boundary_arn" {
  type    = string
  default = null
}
