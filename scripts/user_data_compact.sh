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
mkdir -p /opt/app
cd /opt/app

# Create minimal .env file (no secrets)
cat > .env <<EOF
AWS_REGION=${region}
DB_SECRET_NAME=${db_secret_name}
PROJECT_NAME=${project_name}
ENVIRONMENT=production
EOF
chmod 600 .env

# Create application structure
mkdir -p frontend/public backend configs/nginx

# Download application files from GitHub/S3 or create inline
echo "$(date): Creating application files"

# Frontend HTML
cat > frontend/public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>My Project</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        button { background: #007bff; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 5px; }
        .result { margin-top: 20px; padding: 15px; border-radius: 5px; background: #f8f9fa; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Hello World from CloudFront!</h1>
        <p>Secure application with Docker + Terraform</p>
        <button onclick="testAPI()">Test API</button>
        <button onclick="testDB()">Test Database</button>
        <button onclick="testUsers()">Get Users</button>
        <div id="result"></div>
    </div>
    <script>
        async function testAPI() {
            try {
                const response = await fetch('/api/hello');
                const data = await response.json();
                document.getElementById('result').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
            } catch (error) {
                document.getElementById('result').innerHTML = 'Error: ' + error.message;
            }
        }
        async function testDB() {
            try {
                const response = await fetch('/api/db-test');
                const data = await response.json();
                document.getElementById('result').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
            } catch (error) {
                document.getElementById('result').innerHTML = 'Error: ' + error.message;
            }
        }
        async function testUsers() {
            try {
                const response = await fetch('/api/users');
                const data = await response.json();
                document.getElementById('result').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
            } catch (error) {
                document.getElementById('result').innerHTML = 'Error: ' + error.message;
            }
        }
    </script>
</body>
</html>
EOF

# Backend requirements
cat > backend/requirements.txt <<EOF
Flask==2.3.3
psycopg2-binary==2.9.7
boto3==1.28.85
gunicorn==21.2.0
EOF

# Download secure backend app
curl -o backend/app-secure.py https://raw.githubusercontent.com/example/apps/main/app-secure.py || cat > backend/app-secure.py <<'PYEOF'
# Fallback secure Flask app will be created inline if download fails
from flask import Flask, jsonify, request
import psycopg2, os, json, boto3, re
from botocore.exceptions import ClientError

app = Flask(__name__)

def get_db_credentials():
    secret_name = os.environ.get('DB_SECRET_NAME')
    region = os.environ.get('AWS_REGION', 'eu-central-1')
    client = boto3.client('secretsmanager', region_name=region)
    try:
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        print(f"Error: {e}")
        return None

def get_db_connection():
    creds = get_db_credentials()
    if not creds: return None
    try:
        return psycopg2.connect(
            host=creds['host'], port=creds['port'], 
            database=creds['dbname'], user=creds['username'], 
            password=creds['password'])
    except Exception as e:
        print(f"DB Error: {e}")
        return None

@app.route('/health')
def health(): return "OK"

@app.route('/api/hello')
def hello():
    return jsonify({'message': 'Hello from Backend!', 'status': 'success'})

@app.route('/api/db-test')
def db_test():
    conn = get_db_connection()
    if not conn: return jsonify({'error': 'DB connection failed'}), 500
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT version()")
        version = cursor.fetchone()[0]
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'users'")
        table_exists = cursor.fetchone()[0] > 0
        if table_exists:
            cursor.execute("SELECT COUNT(*) FROM users")
            user_count = cursor.fetchone()[0]
        else:
            user_count = 0
        return jsonify({'status': 'success', 'db_version': version, 'user_count': user_count})
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

@app.route('/api/users')
def get_users():
    conn = get_db_connection()
    if not conn: return jsonify({'error': 'DB connection failed'}), 500
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 10")
        users = cursor.fetchall()
        return jsonify({'users': [{'id': u[0], 'name': u[1], 'email': u[2], 'created_at': str(u[3])} for u in users]})
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

if __name__ == '__main__': app.run(host='0.0.0.0', port=80, debug=False)
PYEOF

# Migration script
cat > backend/migrate.py <<'PYEOF'
#!/usr/bin/env python3
import os, sys, json, boto3, psycopg2

def get_db_credentials():
    secret_name = os.environ.get('DB_SECRET_NAME')
    region = os.environ.get('AWS_REGION', 'eu-central-1')
    client = boto3.client('secretsmanager', region_name=region)
    try:
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        print(f"Error: {e}")
        return None

def run_migrations():
    creds = get_db_credentials()
    if not creds: sys.exit(1)
    try:
        conn = psycopg2.connect(
            host=creds['host'], port=creds['port'], 
            database=creds['dbname'], user=creds['username'], 
            password=creds['password'])
        cursor = conn.cursor()
        cursor.execute('''CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP)''')
        cursor.execute('''INSERT INTO users (name, email) VALUES 
            ('Alice Johnson', 'alice@example.com'),
            ('Bob Smith', 'bob@example.com'),
            ('Charlie Brown', 'charlie@example.com')
            ON CONFLICT (email) DO NOTHING''')
        conn.commit()
        print("Migrations completed")
    except Exception as e:
        print(f"Migration failed: {e}")
        sys.exit(1)
    finally:
        if conn: conn.close()

if __name__ == "__main__": run_migrations()
PYEOF

chmod +x backend/migrate.py

# Nginx config with security headers
cat > configs/nginx/nginx.conf <<'NGEOF'
upstream backend { server backend:80; }
upstream frontend { server frontend:3000; }

add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

server {
    listen 80;
    server_name _;
    server_tokens off;
    
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /health {
        access_log off;
        allow 10.0.0.0/8;
        deny all;
        return 200 '{"status":"healthy"}';
        add_header Content-Type application/json;
    }
    
    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location ~* \.(php|asp|aspx)$ { deny all; return 444; }
    location ~* /\.(ht|git|env) { deny all; return 444; }
}
NGEOF

# Docker Compose with security
cat > docker-compose.yml <<'DCEOF'
version: '3.8'
services:
  nginx:
    image: nginx:alpine
    ports: ["80:80"]
    volumes: ["./configs/nginx/nginx.conf:/etc/nginx/conf.d/default.conf"]
    depends_on: [frontend, backend]
    restart: unless-stopped
    networks: [app-network]

  frontend:
    image: node:18-alpine
    working_dir: /app
    user: "1000:1000"
    environment: ["NODE_ENV=production"]
    volumes: ["./frontend:/app"]
    command: sh -c "cd /app/public && python3 -m http.server 3000"
    expose: ["3000"]
    restart: unless-stopped
    networks: [app-network]
    security_opt: ["no-new-privileges:true"]
    read_only: true
    tmpfs: ["/tmp"]

  backend:
    image: python:3.11-slim
    working_dir: /app
    user: "1000:1000"
    env_file: ["/opt/app/.env"]
    volumes: ["./backend:/app"]
    command: sh -c "apt-get update && apt-get install -y gcc && pip install -r requirements.txt && python migrate.py && gunicorn --bind 0.0.0.0:80 --workers 2 --user 1000 --group 1000 app-secure:app"
    expose: ["80"]
    restart: unless-stopped
    networks: [app-network]
    security_opt: ["no-new-privileges:true"]
    read_only: true
    tmpfs: ["/tmp", "/var/log"]

networks:
  app-network:
    driver: bridge
DCEOF

# Set secure permissions
chown -R ec2-user:ec2-user /opt/app

# Start application
echo "$(date): Starting application with Docker Compose"
docker-compose up -d

# Wait and verify
sleep 30
echo "$(date): Verifying services"
docker-compose ps
curl -f http://localhost/health || echo "Health check failed"

echo "$(date): User data script completed successfully"