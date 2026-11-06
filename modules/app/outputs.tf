output "alb_arn" { value = aws_lb.this.arn }
output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "target_group_arn_suffix" { value = aws_lb_target_group.api.arn_suffix }
output "task_security_group_id" { value = aws_security_group.task.id }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "service_name" { value = aws_ecs_service.api.name }
output "log_group_name" { value = aws_cloudwatch_log_group.api.name }
