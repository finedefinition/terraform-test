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
