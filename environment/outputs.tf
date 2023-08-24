output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}


output "lb_dns_name" {
  description = "The DNS name of the load balancer."
  value       = module.alb.lb_dns_name
}

output "lb_arn" {
  description = "The ID and ARN of the load balancer we created."
  value       = module.alb.lb_arn
}

output "lb_security_group" {
  description = "The security group of the load balancer."
  value       = module.alb.security_group_id
}

output "target_group_arns" {
  description = "ARNs of the target groups. Useful for passing to your Auto Scaling group."
  value       = module.alb.target_group_arns
}

output "elk_endpoint" {
  description = "Endpoint of the elasticsearch domain"
  value       = aws_elasticsearch_domain.es.endpoint
}
output "elk_kibana_endpoint" {
  description = "Endpoint of the elasticsearch Kibana endpoint"
  value       = aws_elasticsearch_domain.es.kibana_endpoint
}
