terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure with backend-config.hcl
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = var.default_tags
  }
}

# US East 1 provider for CloudFront WAF
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  
  default_tags {
    tags = var.default_tags
  }
}

module "vpc" {
  source = "../../shared/modules/vpc"

  project_name       = var.project_name
  environment       = var.environment
  vpc_cidr          = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnets    = var.public_subnets
  private_subnets   = var.private_subnets
  enable_nat_gateway = var.enable_nat_gateway
  enable_vpn_gateway = var.enable_vpn_gateway
  default_tags      = var.default_tags
}

module "security" {
  source = "../../shared/modules/security"

  project_name           = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  admin_cidr            = var.admin_cidr
  aws_region            = var.aws_region
  default_tags          = var.default_tags
}

module "database" {
  source = "../../shared/modules/database"

  project_name               = var.project_name
  environment               = var.environment
  private_subnet_ids        = module.vpc.private_subnets
  database_security_group_id = module.security.database_security_group_id

  db_name                   = var.db_name
  db_username               = var.db_username
  db_instance_class         = var.db_instance_class
  db_engine_version         = var.db_engine_version
  db_allocated_storage      = var.db_allocated_storage
  db_max_allocated_storage  = var.db_max_allocated_storage
  enable_enhanced_monitoring = var.enable_enhanced_monitoring
  enable_performance_insights = var.enable_performance_insights
  
  default_tags = var.default_tags
}

module "compute" {
  source = "../../shared/modules/compute"

  project_name                = var.project_name
  environment                = var.environment
  aws_region                 = var.aws_region
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnets
  private_subnet_ids         = module.vpc.private_subnets
  web_security_group_id      = module.security.web_security_group_id
  ec2_rds_security_group_id  = module.security.ec2_rds_security_group_id
  ec2_instance_profile_name  = module.security.ec2_instance_profile_name
  db_secret_name            = module.database.db_secret_name

  instance_type     = var.instance_type
  key_pair_name     = var.key_pair_name
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  
  default_tags = var.default_tags
}

module "s3_apps" {
  source = "../../shared/modules/s3-apps"

  project_name = var.project_name
  environment  = var.environment
  default_tags = var.default_tags
}

module "cloudfront" {
  source = "../../shared/modules/cloudfront"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name   = var.project_name
  alb_dns_name   = module.compute.alb_dns_name
  default_tags   = var.default_tags
}
