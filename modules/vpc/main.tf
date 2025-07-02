module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = true
  enable_vpn_gateway     = var.enable_vpn_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = merge(var.default_tags, {
    Name = "${var.project_name}-vpc"
  })

  public_subnet_tags = {
    Name = "${var.project_name}-public-subnet"
    Type = "Public"
    Tier = "Web"
  }

  private_subnet_tags = {
    Name = "${var.project_name}-private-subnet"
    Type = "Private" 
    Tier = "Database"
  }

  public_route_table_tags = {
    Name = "${var.project_name}-public-rt"
  }

  private_route_table_tags = {
    Name = "${var.project_name}-private-rt"
  }

  nat_gateway_tags = {
    Name = "${var.project_name}-nat-gateway"
  }

  igw_tags = {
    Name = "${var.project_name}-igw"
  }
}
