from flask import Flask, jsonify, request
import psycopg2
import os
import json
import boto3
from botocore.exceptions import ClientError

app = Flask(__name__)

def get_db_credentials():
    """Get database credentials from AWS Secrets Manager"""
    secret_name = os.environ.get('DB_SECRET_NAME', 'my-project-db-password')
    region_name = os.environ.get('AWS_DEFAULT_REGION', 'eu-central-1')
    
    print(f"[LOG] Attempting to retrieve secret: {secret_name} from region: {region_name}")
    
    # Use EC2 instance metadata for credentials in Docker
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name,
        # Force use of instance metadata
        aws_access_key_id=None,
        aws_secret_access_key=None
    )
    
    try:
        print(f"[LOG] Calling Secrets Manager for secret: {secret_name}")
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        print(f"[LOG] Successfully retrieved secret with keys: {list(secret.keys())}")
        print(f"[LOG] Database endpoint: {secret.get('endpoint', 'NOT_FOUND')}")
        print(f"[LOG] Database port: {secret.get('port', 'NOT_FOUND')}")
        print(f"[LOG] Database name: {secret.get('dbname', 'NOT_FOUND')}")
        print(f"[LOG] Database username: {secret.get('username', 'NOT_FOUND')}")
        return secret
    except ClientError as e:
        print(f"[ERROR] Error retrieving secret: {e}")
        print(f"[ERROR] Error code: {e.response['Error']['Code']}")
        print(f"[ERROR] Error message: {e.response['Error']['Message']}")
        return None
    except Exception as e:
        print(f"[ERROR] Unexpected error retrieving secret: {e}")
        return None

def get_db_connection():
    """Create database connection"""
    print(f"[LOG] Starting database connection process...")
    credentials = get_db_credentials()
    if not credentials:
        print(f"[ERROR] No credentials received from Secrets Manager")
        return None
    
    try:
        # AWS RDS uses 'endpoint' instead of 'host'
        host = credentials.get('endpoint') or credentials.get('host')
        port = credentials['port']
        database = credentials['dbname']
        user = credentials['username']
        
        print(f"[LOG] Attempting to connect to database:")
        print(f"[LOG] Host: {host}")
        print(f"[LOG] Port: {port}")
        print(f"[LOG] Database: {database}")
        print(f"[LOG] User: {user}")
        
        conn = psycopg2.connect(
            host=host,
            port=port,
            database=database,
            user=user,
            password=credentials['password'],
            connect_timeout=10
        )
        print(f"[LOG] Successfully connected to database!")
        return conn
    except psycopg2.OperationalError as e:
        print(f"[ERROR] PostgreSQL operational error: {e}")
        print(f"[ERROR] This usually indicates network connectivity or authentication issues")
        return None
    except psycopg2.Error as e:
        print(f"[ERROR] PostgreSQL error: {e}")
        return None
    except Exception as e:
        print(f"[ERROR] Unexpected database connection error: {e}")
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
    """Test database connection"""
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
        
        return jsonify({
            'status': 'success',
            'database_version': db_version,
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
    """Get all users"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT id, name, email, created_at FROM users ORDER BY created_at DESC")
        users = cursor.fetchall()
        
        return jsonify({
            'users': [
                {
                    'id': user[0],
                    'name': user[1],
                    'email': user[2],
                    'created_at': user[3].isoformat() if user[3] else None
                }
                for user in users
            ],
            'count': len(users)
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

@app.route('/api/users', methods=['POST'])
def create_user():
    """Create a new user"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        data = request.get_json()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING id",
            (data['name'], data['email'])
        )
        user_id = cursor.fetchone()[0]
        conn.commit()
        
        return jsonify({
            'message': 'User created successfully',
            'user_id': user_id
        }), 201
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)