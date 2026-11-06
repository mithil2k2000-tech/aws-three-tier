output "url" { value = module.edge.url }
output "site_bucket" { value = module.edge.site_bucket }
output "distribution_id" { value = module.edge.distribution_id }
output "cluster_name" { value = module.app.cluster_name }
output "service_name" { value = module.app.service_name }
output "dashboard" { value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${module.observability.dashboard_name}" }
output "image" { value = var.image }
