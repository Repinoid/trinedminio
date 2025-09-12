#!/bin/sh

export HADOOP_HOME=/opt/hadoop-3.2.0
export HADOOP_CLASSPATH=${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:${HADOOP_HOME}/share/hadoop/common/lib/*
export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}

echo "Waiting for database on ${METASTORE_DB_HOSTNAME} to launch on 3306 ..."

# Ожидаем доступности MariaDB
while ! nc -z ${METASTORE_DB_HOSTNAME} 3306; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:3306 started"

# Проверяем, инициализирована ли уже схема
echo "Checking if schema is already initialized..."
if /opt/apache-hive-metastore-3.0.0-bin/bin/schematool -dbType mysql -info; then
    echo "Schema is already initialized, skipping initSchema"
else
    echo "Initializing apache hive metastore schema on ${METASTORE_DB_HOSTNAME}:3306"
    # Используем флаг -ifNotExists для избежания ошибок с существующими таблицами
    /opt/apache-hive-metastore-3.0.0-bin/bin/schematool -initSchema -dbType mysql -ifNotExists
    
    # Проверяем успешность инициализации
    if [ $? -eq 0 ]; then
        echo "Schema initialized successfully"
    else
        echo "Schema initialization may have had issues, but continuing..."
    fi
fi

echo "Starting Metastore Server"
/opt/apache-hive-metastore-3.0.0-bin/bin/start-metastore