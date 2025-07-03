from flask import Flask, jsonify, request
import psycopg2
import psycopg2.extras
import os
import json
import boto3
import re
from botocore.exceptions import ClientError

app = Flask(__name__)

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
    secret_name = os.environ.get('DB_SECRET_NAME')
    region_name = os.environ.get('AWS_REGION', 'eu-central-1')
    
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
