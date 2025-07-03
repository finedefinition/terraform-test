module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.environment == "production" ? false : true  # HA in prod
  one_nat_gateway_per_az = var.environment == "production" ? true : false
  enable_vpn_gateway     = var.enable_vpn_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = merge(var.default_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
  })

  public_subnet_tags = {
    Name = "${var.project_name}-${var.environment}-public-subnet"
    Type = "Public"
    Tier = "Web"
    Environment = var.environment
  }

  private_subnet_tags = {
    Name = "${var.project_name}-${var.environment}-private-subnet"
    Type = "Private" 
    Tier = "Database"
    Environment = var.environment
  }

  public_route_table_tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
    Environment = var.environment
  }

  private_route_table_tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
    Environment = var.environment
  }

  nat_gateway_tags = {
    Name = "${var.project_name}-${var.environment}-nat-gateway"
    Environment = var.environment
  }

  igw_tags = {
    Name = "${var.project_name}-${var.environment}-igw"
    Environment = var.environment
  }
}
