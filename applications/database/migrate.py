#!/usr/bin/env python3
"""
Database migration script for PostgreSQL
Reads database credentials from AWS Secrets Manager and applies migrations
"""

import os
import sys
import json
import boto3
import psycopg2
from pathlib import Path
from botocore.exceptions import ClientError

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
        print("Failed to get database credentials")
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

def create_migrations_table(conn):
    """Create migrations tracking table if it doesn't exist"""
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version VARCHAR(255) PRIMARY KEY,
            applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    cursor.close()

def get_applied_migrations(conn):
    """Get list of already applied migrations"""
    cursor = conn.cursor()
    cursor.execute("SELECT version FROM schema_migrations ORDER BY version")
    applied = [row[0] for row in cursor.fetchall()]
    cursor.close()
    return applied

def apply_migration(conn, migration_file):
    """Apply a single migration file"""
    migration_name = migration_file.stem
    
    print(f"Applying migration: {migration_name}")
    
    try:
        # Read migration file
        with open(migration_file, 'r') as f:
            sql_content = f.read()
        
        # Execute migration
        cursor = conn.cursor()
        cursor.execute(sql_content)
        
        # Record migration as applied
        cursor.execute(
            "INSERT INTO schema_migrations (version) VALUES (%s)",
            (migration_name,)
        )
        
        conn.commit()
        cursor.close()
        print(f"✅ Migration {migration_name} applied successfully")
        return True
        
    except Exception as e:
        conn.rollback()
        print(f"❌ Failed to apply migration {migration_name}: {e}")
        return False

def main():
    """Main migration function"""
    print("🚀 Starting database migrations...")
    
    # Get database connection
    conn = get_db_connection()
    if not conn:
        print("❌ Could not connect to database")
        sys.exit(1)
    
    try:
        # Create migrations table
        create_migrations_table(conn)
        
        # Get applied migrations
        applied_migrations = get_applied_migrations(conn)
        print(f"Already applied migrations: {applied_migrations}")
        
        # Find migration files
        migrations_dir = Path(__file__).parent / "migrations"
        migration_files = sorted(migrations_dir.glob("*.sql"))
        
        if not migration_files:
            print("No migration files found")
            return
        
        # Apply pending migrations
        pending_count = 0
        for migration_file in migration_files:
            migration_name = migration_file.stem
            
            if migration_name not in applied_migrations:
                if apply_migration(conn, migration_file):
                    pending_count += 1
                else:
                    print("❌ Migration failed, stopping")
                    sys.exit(1)
            else:
                print(f"⏭️  Skipping already applied migration: {migration_name}")
        
        if pending_count == 0:
            print("✅ All migrations are up to date")
        else:
            print(f"✅ Applied {pending_count} new migrations")
            
    finally:
        conn.close()

if __name__ == "__main__":
    main()