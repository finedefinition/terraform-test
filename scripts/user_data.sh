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

# Set secure umask for file creation
umask 077

# Export minimal environment variables (no secrets)
cat > /opt/app/.env <<EOF
# Application Configuration (NO SECRETS)
AWS_REGION=${region}
DB_SECRET_NAME=${db_secret_name}
PROJECT_NAME=${project_name}
ENVIRONMENT=production
EOF

# Set secure permissions
chmod 600 /opt/app/.env

# Deploy application code from S3 or Git
echo "$(date): Deploying application code"

# Create application directories
mkdir -p frontend/public backend
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

# Backend directory with Python Flask app
mkdir -p backend
cat > backend/requirements.txt <<EOF
Flask==2.3.3
psycopg2-binary==2.9.7
boto3==1.28.85
gunicorn==21.2.0
EOF

cat > backend/app.py <<EOF
from flask import Flask, jsonify, request
import psycopg2
import psycopg2.extras
import os
import json
import boto3
import re
from botocore.exceptions import ClientError

app = Flask(__name__)

# Input validation patterns
EMAIL_PATTERN = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
NAME_PATTERN = re.compile(r'^[a-zA-Z\s\-\']{1,100}$')

def validate_email(email):
    """Validate email format"""
    return EMAIL_PATTERN.match(email) is not None

def validate_name(name):
    """Validate name format"""
    return NAME_PATTERN.match(name) is not None

def sanitize_input(value, max_length=255):
    """Sanitize string input"""
    if not isinstance(value, str):
        return None
    return value.strip()[:max_length]

def get_db_credentials():
    """Get database credentials from AWS Secrets Manager"""
    secret_name = os.environ.get('DB_SECRET_NAME', '${db_secret_name}')
    region_name = os.environ.get('AWS_REGION', '${region}')
    
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret
    except ClientError as e:
        print(f"Error retrieving secret: {e}")
        return None

def get_db_connection():
    """Create database connection"""
    credentials = get_db_credentials()
    if not credentials:
        return None
    
    try:
        conn = psycopg2.connect(
            host=credentials['host'],
            port=credentials['port'],
            database=credentials['dbname'],
            user=credentials['username'],
            password=credentials['password']
        )
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        return None

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for ALB"""
    return "OK", 200

@app.route('/api/hello', methods=['GET'])
def hello_world():
    """Simple API endpoint"""
    return jsonify({
        'message': 'Hello World from Backend!',
        'status': 'success',
        'service': 'backend-api',
        'version': '1.0.0'
    })

@app.route('/api/db-test', methods=['GET'])
def database_test():
    """Test database connection and show table info"""
    conn = get_db_connection()
    if not conn:
        return jsonify({
            'error': 'Could not connect to database',
            'status': 'error'
        }), 500
    
    try:
        cursor = conn.cursor()
        
        # Test connection and get database info
        cursor.execute("SELECT version();")
        db_version = cursor.fetchone()[0]
        
        # Check if users table exists
        cursor.execute("""
            SELECT COUNT(*) FROM information_schema.tables 
            WHERE table_name = 'users'
        """)
        table_exists = cursor.fetchone()[0] > 0
        
        if table_exists:
            cursor.execute("SELECT COUNT(*) FROM users")
            user_count = cursor.fetchone()[0]
        else:
            user_count = 0
        
        return jsonify({
            'status': 'success',
            'database_version': db_version,
            'users_table_exists': table_exists,
            'user_count': user_count,
            'message': 'Database connection successful'
        })
        
    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500
    finally:
        if conn:
            conn.close()

@app.route('/api/users', methods=['GET'])
def get_users():
    """Get all users with pagination and filtering"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        # Get query parameters with validation
        limit = min(int(request.args.get('limit', 10)), 100)  # Max 100 items
        offset = max(int(request.args.get('offset', 0)), 0)
        
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        # Use parameterized query to prevent SQL injection
        cursor.execute("""
            SELECT id, name, email, created_at 
            FROM users 
            ORDER BY created_at DESC 
            LIMIT %s OFFSET %s
        """, (limit, offset))
        
        users = cursor.fetchall()
        
        # Get total count
        cursor.execute("SELECT COUNT(*) FROM users")
        total_count = cursor.fetchone()['count']
        
        return jsonify({
            'users': [dict(user) for user in users],
            'count': len(users),
            'total': total_count,
            'limit': limit,
            'offset': offset
        })
        
    except ValueError:
        return jsonify({'error': 'Invalid pagination parameters'}), 400
    except Exception as e:
        return jsonify({'error': 'Database error occurred'}), 500
    finally:
        conn.close()

@app.route('/api/users', methods=['POST'])
def create_user():
    """Create a new user with validation"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        # Validate and sanitize input
        name = sanitize_input(data.get('name'))
        email = sanitize_input(data.get('email'))
        
        if not name or not validate_name(name):
            return jsonify({'error': 'Invalid name format'}), 400
        
        if not email or not validate_email(email):
            return jsonify({'error': 'Invalid email format'}), 400
        
        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database connection failed'}), 500
        
        try:
            cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            
            # Use parameterized query to prevent SQL injection
            cursor.execute("""
                INSERT INTO users (name, email) 
                VALUES (%s, %s) 
                RETURNING id, name, email, created_at
            """, (name, email))
            
            new_user = cursor.fetchone()
            conn.commit()
            
            return jsonify({
                'message': 'User created successfully',
                'user': dict(new_user)
            }), 201
            
        except psycopg2.IntegrityError:
            conn.rollback()
            return jsonify({'error': 'Email already exists'}), 409
        except Exception as e:
            conn.rollback()
            return jsonify({'error': 'Database error occurred'}), 500
        finally:
            conn.close()
            
    except Exception as e:
        return jsonify({'error': 'Invalid request data'}), 400

@app.route('/api/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get a specific user by ID"""
    if user_id <= 0:
        return jsonify({'error': 'Invalid user ID'}), 400
    
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        # Use parameterized query to prevent SQL injection
        cursor.execute("""
            SELECT id, name, email, created_at 
            FROM users 
            WHERE id = %s
        """, (user_id,))
        
        user = cursor.fetchone()
        
        if not user:
            return jsonify({'error': 'User not found'}), 404
        
        return jsonify({'user': dict(user)})
        
    except Exception as e:
        return jsonify({'error': 'Database error occurred'}), 500
    finally:
        conn.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
EOF

cat > backend/migrate.py <<EOF
#!/usr/bin/env python3
import os
import sys
import json
import boto3
import psycopg2
from botocore.exceptions import ClientError

def get_db_credentials():
    secret_name = os.environ.get('DB_SECRET_NAME', '${db_secret_name}')
    region_name = os.environ.get('AWS_REGION', '${region}')
    
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret
    except ClientError as e:
        print(f"Error retrieving secret: {e}")
        return None

def run_migrations():
    credentials = get_db_credentials()
    if not credentials:
        print("Failed to get database credentials")
        sys.exit(1)
    
    try:
        conn = psycopg2.connect(
            host=credentials['host'],
            port=credentials['port'],
            database=credentials['dbname'],
            user=credentials['username'],
            password=credentials['password']
        )
        
        cursor = conn.cursor()
        
        # Create users table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Create indexes
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
        ''')
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
        ''')
        
        # Insert sample data
        cursor.execute('''
            INSERT INTO users (name, email) VALUES 
                ('Alice Johnson', 'alice@example.com'),
                ('Bob Smith', 'bob@example.com'),
                ('Charlie Brown', 'charlie@example.com')
            ON CONFLICT (email) DO NOTHING
        ''')
        
        conn.commit()
        print("Migrations completed successfully")
        
    except Exception as e:
        print(f"Migration failed: {e}")
        sys.exit(1)
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    run_migrations()
EOF

chmod +x backend/migrate.py

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
    user: "1000:1000"
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
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
      - /app/.npm

  backend:
    image: python:3.11-slim
    working_dir: /app
    user: "1000:1000"
    env_file:
      - /opt/app/.env
    volumes:
      - ./backend:/app
    command: >
      sh -c "
        apt-get update && apt-get install -y gcc &&
        pip install --no-cache-dir -r requirements.txt &&
        python migrate.py &&
        gunicorn --bind 0.0.0.0:80 --workers 2 --timeout 60 --user 1000 --group 1000 app:app
      "
    expose:
      - "80"
    restart: unless-stopped
    networks:
      - app-network
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
      - /var/log

networks:
  app-network:
    driver: bridge
DOCKER_COMPOSE_EOF

mkdir -p configs/nginx
cat > configs/nginx/nginx.conf <<'NGINX_EOF'
upstream backend {
    server backend:80;
}

upstream frontend {
    server frontend:3000;
}

# Security headers for all responses
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self';" always;

# Rate limiting
limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=general:10m rate=100r/s;

server {
    listen 80;
    server_name _;
    
    # Security headers
    server_tokens off;
    
    # Rate limiting for API endpoints
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        limit_req_status 429;
        
        proxy_pass http://backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Additional security headers for API
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
    }

    location /health {
        access_log off;
        allow 10.0.0.0/8;  # Only allow internal health checks
        deny all;
        return 200 '{"status":"healthy","timestamp":"now"}';
        add_header Content-Type application/json;
    }

    location / {
        limit_req zone=general burst=200 nodelay;
        
        proxy_pass http://frontend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Cache static assets
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Block common attack patterns
    location ~* \.(php|asp|aspx|jsp)\$ {
        deny all;
        return 444;
    }
    
    # Block access to sensitive files
    location ~* /\.(ht|git|svn|env) {
        deny all;
        return 444;
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