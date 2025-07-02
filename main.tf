module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  vpc_cidr          = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnets    = var.public_subnets
  private_subnets   = var.private_subnets
  enable_nat_gateway = var.enable_nat_gateway
  enable_vpn_gateway = var.enable_vpn_gateway
  default_tags      = var.default_tags
}

module "security" {
  source = "./modules/security"

  project_name           = var.project_name
  vpc_id                = module.vpc.vpc_id
  admin_cidr            = var.admin_cidr
  aws_region            = var.aws_region
  default_tags          = var.default_tags
}

module "database" {
  source = "./modules/database"

  project_name               = var.project_name
  environment               = var.environment
  private_subnet_ids        = module.vpc.private_subnets
  database_security_group_id = module.security.database_security_group_id
  
  # Database configuration
  db_instance_class         = var.db_instance_class
  db_allocated_storage      = var.db_allocated_storage
  enable_enhanced_monitoring = var.enable_enhanced_monitoring
  enable_performance_insights = var.enable_performance_insights
  
  default_tags = var.default_tags
}
