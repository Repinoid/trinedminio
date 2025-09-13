#!/bin/sh

# Set environment variables
export HADOOP_HOME=/opt/hadoop-3.2.0
export HADOOP_PREFIX=$HADOOP_HOME
export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}

# Set Hive home
export HIVE_HOME=/opt/hive
export PATH=$HADOOP_HOME/bin:$JAVA_HOME/bin:$HIVE_HOME/bin:$PATH

# Set Hadoop classpath
export HADOOP_CLASSPATH="
${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:\
${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:\
${HADOOP_HOME}/share/hadoop/common/lib/*"

echo "=== Environment Setup ==="
echo "HADOOP_HOME: $HADOOP_HOME"
echo "HIVE_HOME: $HIVE_HOME" 
echo "JAVA_HOME: $JAVA_HOME"
echo "METASTORE_DB_HOSTNAME: $METASTORE_DB_HOSTNAME"

# Test basic commands
echo "=== Testing Commands ==="
java -version && echo "Java: OK" || echo "Java: FAILED"
hadoop version && echo "Hadoop: OK" || echo "Hadoop: FAILED"
/opt/hive/bin/schematool -help >/dev/null 2>&1 && echo "Schematool: OK" || echo "Schematool: FAILED"

echo "Waiting for PostgreSQL on ${METASTORE_DB_HOSTNAME} to launch on 5432 ..."

# Wait for PostgreSQL
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${METASTORE_DB_HOSTNAME}/5432" 2>/dev/null; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:5432 started"
echo "Waiting for PostgreSQL to be ready..."
sleep 10  # Увеличиваем время ожидания

echo "=== Database Connection Test ==="
# Test PostgreSQL connection
if PGPASSWORD=hive psql -h $METASTORE_DB_HOSTNAME -U hive -d metastore -c "SELECT 1" >/dev/null 2>&1; then
    echo "PostgreSQL connection: OK"
else
    echo "PostgreSQL connection: FAILED"
    echo "Trying to create database if it doesn't exist..."
    PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE DATABASE metastore;" 2>/dev/null
    PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE USER hive WITH PASSWORD 'hive';" 2>/dev/null
    PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE metastore TO hive;" 2>/dev/null
fi

echo "=== Schema Initialization ==="
# Initialize schema with retries
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Checking schema (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
    if /opt/hive/bin/schematool -dbType postgres -info; then
        echo "Schema is already initialized"
        break
    else
        echo "Schema not initialized, attempting initialization..."
        /opt/hive/bin/schematool -initSchema -dbType postgres -verbose
        
        if [ $? -eq 0 ]; then
            echo "Schema initialized successfully"
            break
        else
            echo "Schema initialization failed, retrying..."
            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 5
        fi
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "WARNING: Schema initialization failed after $MAX_RETRIES attempts, continuing anyway..."
fi

echo "=== Starting Metastore Server ==="
echo "Starting metastore with: /opt/hive/bin/hive --service metastore --verbose"

# Start metastore with verbose output and keep it running
exec /opt/hive/bin/hive --service metastore --verbose
