output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "web_security_group_id" {
  description = "ID of the web security group"
  value       = module.security.web_security_group_id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = module.security.database_security_group_id
}

output "ec2_rds_security_group_id" {
  description = "ID of the EC2 to RDS security group"
  value       = module.security.ec2_rds_security_group_id
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = module.database.db_instance_endpoint
}

output "db_secret_name" {
  description = "Name of the database secret in Secrets Manager"
  value       = module.database.db_secret_name
}

output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.compute.alb_dns_name
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.asg_name
}

output "frontend_bucket_name" {
  description = "Name of the S3 bucket for frontend assets"
  value       = module.cloudfront.frontend_bucket_name
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = "https://${module.cloudfront.cloudfront_domain_name}"
}
