#!/bin/sh

export HADOOP_HOME=/opt/hadoop-3.2.0
export HADOOP_CLASSPATH="
${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:\
${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:\
${HADOOP_HOME}/share/hadoop/common/lib/*"

export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}

echo "Waiting for PostgreSQL on ${METASTORE_DB_HOSTNAME} to launch on 5432 ..."

# Ожидаем доступности PostgreSQL
while ! nc -z ${METASTORE_DB_HOSTNAME} 5432; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:5432 started"

# Дополнительная проверка, что PostgreSQL готов принимать соединения
echo "Waiting for PostgreSQL to be ready..."
sleep 5

echo "Checking if schema is already initialized..."
if /opt/apache-hive-metastore-3.0.0-bin/bin/schematool -dbType postgres -info; then
    echo "Schema is already initialized, skipping initSchema"
else
    echo "Initializing apache hive metastore schema on ${METASTORE_DB_HOSTNAME}:5432"
    /opt/apache-hive-metastore-3.0.0-bin/bin/schematool -initSchema -dbType postgres
    
    if [ $? -eq 0 ]; then
        echo "Schema initialized successfully"
    else
        echo "Schema initialization failed, but continuing..."
    fi
fi

echo "Starting Metastore Server"
/opt/apache-hive-metastore-3.0.0-bin/bin/start-metastore
