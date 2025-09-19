#!/bin/sh

# ==================================================
# НАСТРОЙКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ
# ==================================================

# Путь к установленному Hadoop
export HADOOP_HOME=/opt/hadoop-3.2.0

# Classpath для Hadoop с библиотеками AWS
export HADOOP_CLASSPATH="
${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:\
${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:\
${HADOOP_HOME}/share/hadoop/common/lib/*"

# Установка версии Java
export JAVA_HOME=/usr/local/openjdk-8
export PATH=$PATH:${JAVA_HOME}/bin:${HADOOP_HOME}/bin

# Параметры подключения к базе данных
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}
export METASTORE_DB_PORT=${DB_PORT:-3306}
export METASTORE_DB_NAME=${METASTORE_DB_NAME:-metastore}
export METASTORE_DB_USER=${METASTORE_DB_USER:-hive}
export METASTORE_DB_PASSWORD=${METASTORE_DB_PASSWORD:-hivepassword}

# ==================================================
# ПРОВЕРКА И НАСТРОЙКА СРЕДЫ
# ==================================================

echo "Checking environment configuration..."

# Проверка HADOOP_HOME
if [ ! -d "$HADOOP_HOME" ]; then
    echo "ERROR: HADOOP_HOME directory $HADOOP_HOME does not exist!"
    # exit 1
fi

# Проверка JAVA_HOME
if [ ! -d "$JAVA_HOME" ]; then
    echo "ERROR: JAVA_HOME directory $JAVA_HOME does not exist!"
    # exit 1
fi

# Проверка наличия schematool
if [ ! -f "/opt/hive/bin/schematool" ]; then
    echo "ERROR: schematool not found at /opt/hive/bin/schematool"
    find / -name "schematool" -type f 2>/dev/null
    # exit 1
fi

# ==================================================
# ОЖИДАНИЕ БАЗЫ ДАННЫХ
# ==================================================

echo "Waiting for database on ${METASTORE_DB_HOSTNAME}:${METASTORE_DB_PORT} to launch..."

while ! nc -z ${METASTORE_DB_HOSTNAME} ${METASTORE_DB_PORT}; do
    sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:${METASTORE_DB_PORT} started"

# ==================================================
# ДИАГНОСТИКА (опционально, для отладки)
# ==================================================

echo "=== Environment Diagnostics ==="
echo "HADOOP_HOME: $HADOOP_HOME"
echo "JAVA_HOME: $JAVA_HOME"
echo "JAVA version:"
java -version 2>&1
echo "HADOOP version:"
hadoop version 2>&1 || echo "Hadoop command not available"

# ==================================================
# ИНИЦИАЛИЗАЦИЯ СХЕМЫ БАЗЫ ДАННЫХ
# ==================================================

echo "Checking if schema is already initialized..."

# Проверяем, инициализирована ли уже схема :cite[8]
if /opt/hive/bin/schematool -dbType mysql -info; then
    echo "Schema is already initialized, skipping initSchema"
else
    echo "Initializing apache hive metastore schema on ${METASTORE_DB_HOSTNAME}:${METASTORE_DB_PORT}"
    
    # Инициализируем схему с флагом -ifNotExists :cite[1]
    /opt/hive/bin/schematool -initSchema -dbType mysql -ifNotExists
    
    # Проверяем успешность инициализации
    if [ $? -eq 0 ]; then
        echo "Schema initialized successfully"
    else
        echo "WARNING: Schema initialization may have had issues"
        echo "Continuing anyway - metastore might work with existing schema"
    fi
fi

# ==================================================
# ЗАПУСК HIVE METASTORE SERVER
# ==================================================

echo "Starting Hive Metastore Server"

# Запускаем Hive Metastore напрямую через Java :cite[6]
# Поскольку скрипт start-metastore отсутствует в образе
exec java \
    -Xmx2g \
    -Djavax.jdo.option.ConnectionURL="jdbc:mysql://${METASTORE_DB_HOSTNAME}:${METASTORE_DB_PORT}/${METASTORE_DB_NAME}?createDatabaseIfNotExist=true" \
    -Djavax.jdo.option.ConnectionDriverName="org.mariadb.jdbc.Driver" \
    -Djavax.jdo.option.ConnectionUserName="${METASTORE_DB_USER}" \
    -Djavax.jdo.option.ConnectionPassword="${METASTORE_DB_PASSWORD}" \
    -Dhive.metastore.schema.verification=false \
    -Dhive.metastore.event.db.notification.api.auth=false \
    -Dhive.metastore.warehouse.dir="/user/hive/warehouse" \
    -Dhive.metastore.thrift.uris="thrift://0.0.0.0:9083" \
    -cp "/opt/hive/lib/*:${HADOOP_HOME}/share/hadoop/common/lib/*" \
    org.apache.hadoop.hive.metastore.HiveMetaStore

tail -f /dev/null