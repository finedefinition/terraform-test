#!/bin/bash
set -e

# Logging setup
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "$(date): Starting user data script"

# Update system
yum update -y

# Install essential packages
yum install -y \
    docker \
    git \
    curl \
    unzip \
    jq

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install and configure SSM Agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Get database credentials from Secrets Manager
echo "$(date): Retrieving database credentials"
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_name}" \
  --region "${region}" \
  --query SecretString --output text)

# Parse database credentials
DB_HOST=$(echo $DB_SECRET | jq -r '.endpoint')
DB_PORT=$(echo $DB_SECRET | jq -r '.port')
DB_NAME=$(echo $DB_SECRET | jq -r '.dbname')
DB_USER=$(echo $DB_SECRET | jq -r '.username')
DB_PASSWORD=$(echo $DB_SECRET | jq -r '.password')

# Export environment variables
cat > /opt/app/.env <<EOF
# Database Configuration
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME

# Application Configuration
NODE_ENV=production
PORT=3000
AWS_REGION=${region}
DB_SECRET_NAME=${db_secret_name}
PROJECT_NAME=${project_name}
EOF

# Create sample application structure
echo "$(date): Creating sample application structure"

# Frontend directory with sample React app
mkdir -p frontend/public frontend/src
cat > frontend/package.json <<EOF
{
  "name": "${project_name}-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "serve": "npx serve -s build -l 3000"
  },
  "eslintConfig": {
    "extends": ["react-app"]
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version", "last 1 safari version"]
  }
}
EOF

cat > frontend/public/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${project_name} Frontend</title>
</head>
<body>
    <div id="root">
        <h1>Welcome to ${project_name}</h1>
        <p>Frontend is running!</p>
        <button onclick="testApi()">Test API</button>
        <div id="api-result"></div>
    </div>
    <script>
        async function testApi() {
            try {
                const response = await fetch('/api/health');
                const data = await response.json();
                document.getElementById('api-result').innerHTML = 
                    '<p>API Response: ' + JSON.stringify(data) + '</p>';
            } catch (error) {
                document.getElementById('api-result').innerHTML = 
                    '<p>API Error: ' + error.message + '</p>';
            }
        }
    </script>
</body>
</html>
EOF

# Backend directory with sample Node.js app
mkdir -p backend
cat > backend/package.json <<EOF
{
  "name": "${project_name}-backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.8.0",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3"
  },
  "scripts": {
    "start": "node server.js",
    "migrate": "node migrate.js"
  }
}
EOF

cat > backend/server.js <<EOF
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// Health check endpoint
app.get('/api/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as timestamp');
    res.json({
      status: 'healthy',
      database: 'connected',
      timestamp: result.rows[0].timestamp,
      instance_id: process.env.HOSTNAME || 'unknown'
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      database: 'disconnected',
      error: error.message
    });
  }
});

// Sample API endpoint
app.get('/api/users', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM users LIMIT 10');
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(port, () => {
  console.log('${project_name} backend listening on port ' + port);
});
EOF

cat > backend/migrate.js <<EOF
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function runMigrations() {
  try {
    console.log('Running database migrations...');
    
    // Create users table
    await pool.query(\`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    \`);
    
    // Insert sample data
    await pool.query(\`
      INSERT INTO users (name, email) VALUES 
        ('John Doe', 'john@example.com'),
        ('Jane Smith', 'jane@example.com')
      ON CONFLICT (email) DO NOTHING
    \`);
    
    console.log('Migrations completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }
}

runMigrations();
EOF

# Copy Docker Compose and Nginx configs
echo "$(date): Setting up Docker configuration"
aws s3 cp s3://terraform-configurations-bucket/docker-compose.yml . || \
curl -o docker-compose.yml https://raw.githubusercontent.com/example/configs/main/docker-compose.yml || \
cat > docker-compose.yml <<'DOCKER_COMPOSE_EOF'
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./configs/nginx/nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - frontend
      - backend
    restart: unless-stopped
    networks:
      - app-network

  frontend:
    image: node:18-alpine
    working_dir: /app
    environment:
      - NODE_ENV=production
      - REACT_APP_API_URL=/api
    volumes:
      - ./frontend:/app
      - /app/node_modules
    command: >
      sh -c "
        npm install --production &&
        if [ -f package.json ] && grep -q 'build' package.json; then
          npm run build && npx serve -s build -l 3000
        else
          python3 -m http.server 3000
        fi
      "
    expose:
      - "3000"
    restart: unless-stopped
    networks:
      - app-network

  backend:
    image: node:18-alpine
    working_dir: /app
    env_file:
      - /opt/app/.env
    volumes:
      - ./backend:/app
      - /app/node_modules
    command: >
      sh -c "
        npm install --production &&
        npm run migrate &&
        npm start
      "
    expose:
      - "3000"
    restart: unless-stopped
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
DOCKER_COMPOSE_EOF

mkdir -p configs/nginx
cat > configs/nginx/nginx.conf <<'NGINX_EOF'
upstream backend {
    server backend:3000;
}

upstream frontend {
    server frontend:3000;
}

server {
    listen 80;
    server_name _;

    location /health {
        access_log off;
        return 200 '{"status":"healthy","timestamp":"now"}';
        add_header Content-Type application/json;
    }

    location /api/ {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_EOF

# Set permissions
chown -R ec2-user:ec2-user /opt/app

# Start the application
echo "$(date): Starting application with Docker Compose"
cd /opt/app
docker-compose up -d

# Wait for services to start
sleep 30

# Verify services are running
echo "$(date): Verifying services"
docker-compose ps
curl -f http://localhost/health || echo "Health check failed"

echo "$(date): User data script completed successfully"
echo "Application is available at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"