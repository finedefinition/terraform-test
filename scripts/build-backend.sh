#!/bin/bash
set -e

# Build and deploy backend Docker image
# Usage: ./scripts/build-backend.sh [environment]

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🐳 Building backend Docker image for environment: $ENVIRONMENT"

# Change to backend directory
cd "$PROJECT_ROOT/applications/backend"

# Build Docker image
echo "Building Docker image..."
docker build -t my-project-backend:latest .

# Test the image locally
echo "Testing Docker image..."
docker run --rm -d --name test-backend -p 8080:80 my-project-backend:latest

# Wait for container to start
sleep 5

# Test health endpoint
if curl -f -s "http://localhost:8080/health" > /dev/null; then
    echo "✅ Docker image test passed"
else
    echo "❌ Docker image test failed"
    docker logs test-backend
fi

# Stop test container
docker stop test-backend

echo "✅ Backend Docker image built successfully"
echo "Image: my-project-backend:latest"
echo ""
echo "To deploy to production:"
echo "1. Tag and push to ECR"
echo "2. Update launch template with new image"
echo "3. Update Auto Scaling Group"