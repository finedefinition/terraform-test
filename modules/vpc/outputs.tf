output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = module.vpc.vpc_arn
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.igw_id
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "nat_gateway_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = module.vpc.natgw_ids
}

output "nat_gateway_ips" {
  description = "List of public IPs of the NAT Gateways"
  value       = module.vpc.nat_public_ips
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = module.vpc.public_route_table_ids[0]
}

output "private_route_table_ids" {
  description = "List of IDs of the private route tables"
  value       = module.vpc.private_route_table_ids
}