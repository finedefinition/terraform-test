#!/bin/bash
set -e

# Logging setup
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "$(date): Starting user data script"

# Update system and install essential packages
yum update -y
yum install -y docker git curl unzip jq python3 python3-pip

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install SSM Agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Set secure umask
umask 077

# Create application directory
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# Create minimal .env file (no secrets)
cat > .env <<EOF
AWS_DEFAULT_REGION=${region}
DB_SECRET_NAME=${db_secret_name}
PROJECT_NAME=${project_name}
ENVIRONMENT=production
EOF
chmod 600 .env

# Download application files from S3
echo "$(date): Downloading application files from S3"
S3_BUCKET="${project_name}-app-files-${environment}"

# Create directory structure
mkdir -p frontend/public backend configs

# Download files from S3
aws s3 cp s3://$S3_BUCKET/frontend/index.html frontend/public/index.html --region ${region}
aws s3 cp s3://$S3_BUCKET/backend/app.py backend/app.py --region ${region}
aws s3 cp s3://$S3_BUCKET/backend/requirements.txt backend/requirements.txt --region ${region}
aws s3 cp s3://$S3_BUCKET/docker-compose.yml docker-compose.yml --region ${region}
aws s3 cp s3://$S3_BUCKET/nginx.conf configs/nginx.conf --region ${region}

# Set secure permissions
chown -R ec2-user:ec2-user /home/ec2-user/app

# Start application
echo "$(date): Starting application with Docker Compose"
cd /home/ec2-user/app
docker-compose up -d

# Wait and verify
sleep 30
echo "$(date): Verifying services"
docker-compose ps
curl -f http://localhost/health || echo "Health check failed"

echo "$(date): User data script completed successfully"