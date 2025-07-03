#!/bin/bash
set -e

# Deployment script for frontend and backend
# Usage: ./scripts/deploy.sh [environment]

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting deployment for environment: $ENVIRONMENT"

# Change to environment directory
cd "$PROJECT_ROOT/environments/$ENVIRONMENT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    print_step "Initializing Terraform..."
    terraform init -backend-config=backend-config.hcl
fi

# Get terraform outputs
print_step "Getting infrastructure outputs..."
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name 2>/dev/null || echo "")
CLOUDFRONT_DISTRIBUTION=$(terraform output -raw cloudfront_domain_name 2>/dev/null || echo "")

if [ -z "$FRONTEND_BUCKET" ]; then
    print_error "Could not get frontend bucket name from terraform output"
    print_warning "Please run 'terraform apply' first to create infrastructure"
    exit 1
fi

print_step "Infrastructure outputs:"
echo "  Frontend Bucket: $FRONTEND_BUCKET"
echo "  CloudFront Domain: $CLOUDFRONT_DISTRIBUTION"

# Deploy Frontend
print_step "Deploying frontend to S3..."
cd "$PROJECT_ROOT"

# Upload frontend files to S3
aws s3 sync applications/frontend/public/ s3://$FRONTEND_BUCKET --delete --region eu-central-1

# Invalidate CloudFront cache
if [ -n "$CLOUDFRONT_DISTRIBUTION" ]; then
    print_step "Invalidating CloudFront cache..."
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$CLOUDFRONT_DISTRIBUTION'].Id" --output text)
    if [ -n "$DISTRIBUTION_ID" ]; then
        aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"
    fi
fi

# Deploy Backend (Docker)
print_step "Building and deploying backend..."

# Build Docker image
cd "$PROJECT_ROOT/applications/backend"
docker build -t my-project-backend:latest .

# Tag for ECR (if using ECR)
# docker tag my-project-backend:latest $AWS_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com/my-project-backend:latest

# Note: In production, you would push to ECR and update the launch template
# For now, this demonstrates the build process

# Run Database Migrations
print_step "Running database migrations..."
cd "$PROJECT_ROOT/applications/database"

# Install Python dependencies for migration script
pip3 install boto3 psycopg2-binary

# Run migrations
python3 migrate.py

# Test deployment
print_step "Testing deployment..."
cd "$PROJECT_ROOT/environments/$ENVIRONMENT"

# Test frontend
if [ -n "$CLOUDFRONT_DISTRIBUTION" ]; then
    echo "Testing frontend at: https://$CLOUDFRONT_DISTRIBUTION"
    if curl -f -s "https://$CLOUDFRONT_DISTRIBUTION" > /dev/null; then
        print_step "✅ Frontend is accessible"
    else
        print_warning "⚠️  Frontend may not be ready yet (CloudFront propagation takes time)"
    fi
fi

# Test backend health (through ALB)
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
if [ -n "$ALB_DNS" ]; then
    echo "Testing backend health at: http://$ALB_DNS/health"
    if curl -f -s "http://$ALB_DNS/health" > /dev/null; then
        print_step "✅ Backend health check passed"
    else
        print_warning "⚠️  Backend health check failed - check EC2 instances"
    fi
fi

print_step "🎉 Deployment completed!"
echo ""
echo "Access your application at:"
echo "  Frontend: https://$CLOUDFRONT_DISTRIBUTION"
echo "  Backend Health: http://$ALB_DNS/health"
echo "  Backend API: https://$CLOUDFRONT_DISTRIBUTION/api/hello"
echo ""
echo "To monitor deployment:"
echo "  - Check CloudWatch logs for application logs"
echo "  - Check ALB target group health in AWS Console"
echo "  - Check CloudFront distribution status"