# AWS Production-Grade Infrastructure with Terraform

Multi-tier AWS infrastructure for a web application with containerized backend, managed database, CDN delivery, and WAF protection. Built with reusable Terraform modules supporting multiple environments.

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │              Internet                │
                        └────────────┬──────────┬─────────────┘
                                     │          │
                              ┌──────▼───┐  ┌───▼──────┐
                              │CloudFront│  │   WAF    │
                              │  (CDN)   │  │(Web ACL) │
                              └──────┬───┘  └───┬──────┘
                                     │          │
                        ┌────────────▼──────────▼─────────────┐
                        │         Public Subnet (ALB)          │
                        │    ┌──────────────────────────┐      │
                        │    │   Application Load       │      │
                        │    │   Balancer (HTTPS)       │      │
                        │    └────────────┬─────────────┘      │
                        └─────────────────│────────────────────┘
                        ┌─────────────────▼────────────────────┐
                        │        Private Subnet — App Tier      │
                        │    ┌──────────────────────────┐      │
                        │    │  Auto Scaling Group       │      │
                        │    │  EC2 + Docker Compose     │      │
                        │    │  Flask API + Nginx        │      │
                        │    └────────────┬─────────────┘      │
                        └─────────────────│────────────────────┘
                        ┌─────────────────▼────────────────────┐
                        │       Private Subnet — DB Tier        │
                        │    ┌──────────────────────────┐      │
                        │    │   RDS PostgreSQL          │      │
                        │    │   (Multi-AZ, encrypted)   │      │
                        │    └──────────────────────────┘      │
                        └──────────────────────────────────────┘
                        ┌──────────────────────────────────────┐
                        │          S3 + CloudFront              │
                        │    Static frontend (HTML/CSS/JS)      │
                        └──────────────────────────────────────┘
```

## AWS Services

| Service | Purpose |
|---|---|
| VPC | Isolated network with public / private / database subnets |
| EC2 + ASG | Auto Scaling Group with Launch Template for the backend |
| RDS PostgreSQL | Managed relational database in private subnets |
| S3 | Static frontend hosting |
| CloudFront | CDN for frontend delivery and API proxying |
| WAF | Web Application Firewall — rate limiting, IP rules |
| ALB | HTTPS load balancer with health checks |
| Network ACL | Subnet-level traffic control |
| IAM | Least-privilege roles for EC2 and services |

## Module Structure

```
terraform-test/
├── environments/
│   ├── dev/                    # Development environment
│   │   ├── main.tf             # Module composition
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── prod/                   # Production environment
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── shared/
    └── modules/
        ├── vpc/                # VPC, subnets, route tables, IGW
        ├── security/           # Security groups, IAM roles
        ├── compute/            # EC2 ASG + Launch Template
        ├── database/           # RDS PostgreSQL with subnet group
        ├── cloudfront/         # CloudFront distribution + WAF
        ├── s3-apps/            # S3 bucket for static assets
        └── network-acl/        # Network ACL rules
```

## Application Stack

**Backend** — Flask API containerized with Docker Compose, served via Nginx reverse proxy on EC2.

```yaml
# configs/docker-compose.yml (simplified)
services:
  backend:
    build: ./backend
    environment:
      - DB_HOST=${RDS_ENDPOINT}
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
```

**Frontend** — Static HTML/CSS/JS hosted on S3, delivered via CloudFront CDN with custom cache behaviors.

**Database** — PostgreSQL on RDS in isolated private subnets with automated backups enabled.

## Key Design Decisions

**Multi-tier subnet isolation** — three layers: public (ALB), private (EC2), database (RDS). Database tier has no internet route by design.

**Module reuse across environments** — `dev` and `prod` consume the same shared modules with different `terraform.tfvars`. No code duplication.

**WAF on CloudFront** — rate limiting and managed rule sets applied at the CDN edge before traffic reaches EC2.

**ASG with Launch Template** — backend scales horizontally. Nginx handles routing between static frontend proxy and Flask API.

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- S3 bucket for remote state (configure in `backend.tf`)

## Usage

```bash
# Initialize and deploy dev environment
cd environments/dev
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"

# Deploy production
cd environments/prod
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## What's Deployed

- VPC with 3-tier subnet architecture across 2 availability zones
- Auto Scaling Group (min 1, max 3) with EC2 Launch Template
- RDS PostgreSQL with automated backups and encryption at rest
- S3 bucket with versioning + CloudFront distribution
- WAF Web ACL with rate limiting rules
- ALB with HTTPS listener and target group health checks
- Network ACLs for subnet-level traffic control
- IAM roles with least-privilege policies for EC2
