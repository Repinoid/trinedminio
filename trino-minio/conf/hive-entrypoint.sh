#!/bin/bash

# Hive Metastore entrypoint script

set -e

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
while ! nc -z postgres 5432; do
  sleep 1
done
echo "PostgreSQL is up!"

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
while ! nc -z minio 9000; do
  sleep 1
done
echo "MinIO is up!"

# Check if JDBC driver exists
JDBC_DRIVER="/opt/hadoop-3.2.0/share/hadoop/common/lib/postgresql-jdbc.jar"
if [ -f "$JDBC_DRIVER" ]; then
    echo "PostgreSQL JDBC driver found: $JDBC_DRIVER"
    export HADOOP_CLASSPATH="$HADOOP_CLASSPATH:$JDBC_DRIVER"
else
    echo "WARNING: PostgreSQL JDBC driver not found at $JDBC_DRIVER"
fi

# Initialize database schema if not already initialized
echo "Checking if database schema needs initialization..."

# Set proper database type for schema tool
export DB_TYPE=postgres

# Try to initialize schema with explicit database type
SCHEMA_TOOL="/opt/hive/bin/schematool"
if [ -f "$SCHEMA_TOOL" ]; then
    echo "Using schematool: $SCHEMA_TOOL"
    
    # Check if schema is already initialized
    if $SCHEMA_TOOL -dbType postgres -info >/dev/null 2>&1; then
        echo "Database schema already initialized."
    else
        echo "Initializing database schema for PostgreSQL..."
        # Force PostgreSQL driver and connection
        $SCHEMA_TOOL -dbType postgres -initSchema \
            -userName admin \
            -passWord admin \
            -url "jdbc:postgresql://postgres:5432/metastore_db?sslmode=disable"
        
        if [ $? -eq 0 ]; then
            echo "Database schema initialized successfully!"
        else
            echo "WARNING: Schema initialization failed, but continuing..."
            # Try manual initialization if automatic fails
            echo "Trying alternative initialization approach..."
        fi
    fi
else
    echo "WARNING: schematool not found, skipping schema initialization"
fi

# Start Hive Metastore
echo "Starting Hive Metastore..."

# Try different start commands
if [ -f "/opt/hive/bin/start-metastore" ]; then
    echo "Starting with /opt/hive/bin/start-metastore"
    exec /opt/hive/bin/start-metastore
elif [ -f "/opt/hive/bin/hive" ]; then
    echo "Starting with /opt/hive/bin/hive --service metastore"
    exec /opt/hive/bin/hive --service metastore
else
    echo "ERROR: No start script found!"
    echo "Trying to find available commands..."
    find /opt -name "*hive*" -type f | head -10
    exit 1
fi
