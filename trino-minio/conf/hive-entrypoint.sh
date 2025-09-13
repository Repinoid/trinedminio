#!/bin/sh

export HADOOP_HOME=/opt/hadoop-3.2.0
export HADOOP_CLASSPATH="
${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:\
${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:\
${HADOOP_HOME}/share/hadoop/common/lib/*"

export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}

# Set the correct Hive home - use the main hive installation
export HIVE_HOME=/opt/hive

echo "Using Hive installation at: $HIVE_HOME"

echo "Waiting for PostgreSQL on ${METASTORE_DB_HOSTNAME} to launch on 5432 ..."

# Wait for PostgreSQL using bash built-in
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${METASTORE_DB_HOSTNAME}/5432" 2>/dev/null; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:5432 started"

echo "Waiting for PostgreSQL to be ready..."
sleep 5

echo "Checking if schema is already initialized..."
if $HIVE_HOME/bin/schematool -dbType postgres -info; then
    echo "Schema is already initialized, skipping initSchema"
else
    echo "Initializing apache hive metastore schema on ${METASTORE_DB_HOSTNAME}:5432"
    $HIVE_HOME/bin/schematool -initSchema -dbType postgres
    
    if [ $? -eq 0 ]; then
        echo "Schema initialized successfully"
    else
        echo "Schema initialization failed, but continuing..."
    fi
fi

echo "Starting Metastore Server"
# Use the metastore installation for starting the service
/opt/apache-hive-metastore-3.0.0-bin/bin/start-metastore
