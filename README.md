# AWS VPC Terraform Configuration

This Terraform configuration creates a VPC in AWS with public and private subnets across multiple availability zones using native AWS resources and modular structure.

## Project Structure

```
terraform-test/
├── main.tf                     # Root module - orchestrates all modules
├── providers.tf                # Provider configurations
├── backend.tf                  # S3 backend configuration
├── variables.tf                # Root-level input variables
├── outputs.tf                  # Root-level outputs
├── terraform.tfvars.example    # Example variable values
├── backend-config.hcl.example  # Example backend configuration
├── README.md                   # This file
├── .gitignore                  # Git ignore patterns
└── modules/
    ├── vpc/                    # VPC module
    │   ├── main.tf             # VPC resources (terraform-aws-modules)
    │   ├── variables.tf        # Module input variables
    │   └── outputs.tf          # Module outputs
    └── s3/                     # S3 module
        ├── main.tf             # S3 bucket and IAM for configs
        ├── variables.tf        # Module input variables
        └── outputs.tf          # Module outputs
```

## Features

- **Modular Architecture**: VPC resources organized in dedicated module
- **Terraform AWS Modules**: Uses proven `terraform-aws-modules/vpc/aws` module  
- **Multi-AZ Setup**: Public and private subnets across multiple availability zones
- **NAT Gateway**: Optional NAT Gateway for private subnet internet access
- **VPN Gateway**: Optional VPN Gateway for site-to-site connections
- **S3 Backend**: State storage with native S3 locking
- **Comprehensive Tagging**: Consistent resource tagging strategy
- **Project-based Naming**: Resources named with project prefix

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.0)
3. S3 bucket for state storage (create manually)

## Setup

### 1. Create S3 Backend Resources (Manual)

Create the S3 bucket for state management (no DynamoDB needed with S3 native locking):

```bash
# Create S3 bucket (replace with your unique bucket name)
aws s3 mb s3://your-terraform-state-bucket --region us-west-2

# Enable versioning (recommended for state files)
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled
```

### 2. Configure Backend

1. Copy the example backend configuration:
   ```bash
   cp backend-config.hcl.example backend-config.hcl
   ```

2. Edit `backend-config.hcl` with your actual values:
   ```hcl
   bucket       = "your-actual-terraform-state-bucket"
   key          = "vpc/terraform.tfstate"
   region       = "us-west-2"
   encrypt      = true
   use_lockfile = true  # S3 native locking (no DynamoDB needed)
   ```

### 3. Configure Variables

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your specific values.

### 4. Deploy

```bash
# Initialize Terraform with backend configuration
terraform init -backend-config=backend-config.hcl

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

## Configuration

### Root Variables

- `project_name`: Name of your project (used in resource naming)
- `environment`: Environment (dev, staging, prod)
- `aws_region`: AWS region to deploy resources
- `vpc_cidr`: CIDR block for the VPC
- `availability_zones`: List of AZs to use
- `public_subnets`: CIDR blocks for public subnets
- `private_subnets`: CIDR blocks for private subnets
- `enable_nat_gateway`: Enable NAT Gateway for private subnets
- `enable_vpn_gateway`: Enable VPN Gateway
- `app_configs_bucket_name`: Name of S3 bucket for application configs
- `default_tags`: Default tags applied to all resources

### VPC Module

The VPC module creates:
- VPC with DNS hostnames and support enabled
- Internet Gateway
- Public subnets with public IP mapping
- Private subnets
- Route tables and associations
- NAT Gateways (optional, one per AZ)
- Elastic IPs for NAT Gateways
- VPN Gateway (optional)

### S3 Module

The S3 module creates:
- S3 bucket for application configurations (nginx, docker-compose)
- Bucket versioning and encryption
- IAM role and policy for EC2 to access the bucket
- Instance profile for EC2 instances

### Outputs

The configuration provides comprehensive outputs including:
- VPC ID, CIDR, and ARN
- Subnet IDs and CIDRs (public and private)
- Gateway IDs (Internet, NAT, VPN)
- Route table IDs
- NAT Gateway public IPs
- S3 bucket name and ARN for application configs
- IAM instance profile for EC2

## Resource Naming Convention

All resources follow the pattern: `${project_name}-<resource-type>-<identifier>`

Examples:
- `my-project-vpc`
- `my-project-public-subnet-1`
- `my-project-nat-gateway-1`

## Security Best Practices

- State file is encrypted in S3
- Native S3 locking prevents concurrent modifications
- All resources are properly tagged
- Private subnets for secure resources
- NAT Gateway for controlled outbound internet access
- Separate route tables for public and private subnets

## Module Development

To add new modules:
1. Create directory under `modules/`
2. Follow the three-file pattern: `main.tf`, `variables.tf`, `outputs.tf`
3. Add module instantiation to root `main.tf`
4. Update root `variables.tf` and `outputs.tf` as needed

## Clean Up

```bash
terraform destroy
```

Note: You may need to manually delete the S3 bucket after destroying the infrastructure.