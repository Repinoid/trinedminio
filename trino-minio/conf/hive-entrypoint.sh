#!/bin/sh

# Set environment variables
export HADOOP_HOME=/opt/hadoop
export HADOOP_PREFIX=$HADOOP_HOME
export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}
export HIVE_HOME=/opt/hive

export PATH=$HADOOP_HOME/bin:$JAVA_HOME/bin:$HIVE_HOME/bin:$PATH

echo "=== Environment Setup ==="
echo "HADOOP_HOME: $HADOOP_HOME"
echo "JAVA_HOME: $JAVA_HOME"
echo "HIVE_HOME: $HIVE_HOME"

# Wait for PostgreSQL
echo "Waiting for PostgreSQL on ${METASTORE_DB_HOSTNAME} to launch on 5432 ..."
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${METASTORE_DB_HOSTNAME}/5432" 2>/dev/null; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:5432 started"
echo "Waiting for PostgreSQL to be ready..."
sleep 10

echo "=== Setting up PostgreSQL database ==="
# Create database and user
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE DATABASE IF NOT EXISTS metastore;" 2>/dev/null || true
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE USER IF NOT EXISTS hive WITH PASSWORD 'hive';" 2>/dev/null || true
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE metastore TO hive;" 2>/dev/null || true

echo "=== Initializing Hive Schema ==="
# Use schematool instead of direct Java call
if /opt/hive/bin/schematool -dbType postgres -info 2>/dev/null; then
    echo "Schema already initialized"
else
    echo "Initializing schema using schematool..."
    /opt/hive/bin/schematool -initSchema -dbType postgres -verbose
    if [ $? -ne 0 ]; then
        echo "Schema initialization failed, but continuing..."
    fi
fi

echo "=== Starting Hive Metastore ==="
# Find PostgreSQL JDBC driver
POSTGRES_JAR=$(find $HIVE_HOME -name "postgresql*.jar" | head -1)
if [ -z "$POSTGRES_JAR" ]; then
    echo "ERROR: PostgreSQL JDBC driver not found!"
    echo "Looking for JDBC drivers:"
    find $HIVE_HOME -name "*jdbc*.jar" -o -name "*postgres*.jar"
    exit 1
fi

echo "Found PostgreSQL driver: $POSTGRES_JAR"

# Build classpath with all necessary JARs
HIVE_LIB_JARS=$(find $HIVE_HOME/lib -name "*.jar" | tr '\n' ':')
HADOOP_COMMON_JARS=$(find $HADOOP_HOME/share/hadoop/common -name "*.jar" | tr '\n' ':')
HADOOP_HDFS_JARS=$(find $HADOOP_HOME/share/hadoop/hdfs -name "*.jar" | tr '\n' ':')

CLASSPATH="$HIVE_LIB_JARS$HADOOP_COMMON_JARS$HADOOP_HDFS_JARS$POSTGRES_JAR"

echo "Starting Hive Metastore with proper classpath..."
exec java -cp "$CLASSPATH" \
    -Djavax.jdo.option.ConnectionURL="jdbc:postgresql://${METASTORE_DB_HOSTNAME}:5432/metastore" \
    -Djavax.jdo.option.ConnectionDriverName="org.postgresql.Driver" \
    -Djavax.jdo.option.ConnectionUserName="hive" \
    -Djavax.jdo.option.ConnectionPassword="hive" \
    -Dhive.metastore.uris="thrift://0.0.0.0:9083" \
    org.apache.hadoop.hive.metastore.HiveMetaStore
    