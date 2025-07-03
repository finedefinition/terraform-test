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
    app.run(host='0.0.0.0', port=80, debug=False)