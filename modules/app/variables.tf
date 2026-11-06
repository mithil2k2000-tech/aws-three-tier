variable "name" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_ids" { type = list(string) }
variable "kms_key_arn" { type = string }
variable "image" {
  description = "Full image URI with an immutable tag or digest, e.g. <acct>.dkr.ecr.eu-west-2.amazonaws.com/three-tier-api:<git-sha>"
  type        = string
}
variable "cpu" {
  type    = number
  default = 256
}
variable "memory" {
  type    = number
  default = 512
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "max_count" {
  type    = number
  default = 4
}
variable "db_host" { type = string }
variable "db_name" { type = string }
variable "db_secret_arn" { type = string }
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "alb_deletion_protection" {
  type    = bool
  default = true
}
variable "container_insights" {
  type    = bool
  default = true
}
variable "iam_path" {
  type    = string
  default = "/app/three-tier/"
}
variable "permissions_boundary_arn" {
  type    = string
  default = null
}
