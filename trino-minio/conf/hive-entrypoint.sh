#!/bin/sh

# Set environment variables
export HADOOP_HOME=/opt/hadoop-3.2.0
export HADOOP_PREFIX=$HADOOP_HOME
export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}
export HIVE_HOME=/opt/hive

# Add to PATH - важно добавить sbin для Hadoop
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$JAVA_HOME/bin:$HIVE_HOME/bin:$PATH

# Set Hadoop classpath
export HADOOP_CLASSPATH="
${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:\
${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:\
${HADOOP_HOME}/share/hadoop/common/lib/*"

# Проверим и настроим Hadoop конфигурацию
echo "=== Setting up Hadoop environment ==="

# Проверяем существование конфигурационных файлов Hadoop
if [ ! -f "$HADOOP_HOME/etc/hadoop/hadoop-env.sh" ]; then
    echo "Hadoop configuration not found, checking alternative locations..."
    # Ищем конфигурацию Hadoop
    if [ -d "/opt/hadoop/etc/hadoop" ]; then
        export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
        echo "Using Hadoop config from: $HADOOP_CONF_DIR"
    elif [ -d "$HADOOP_HOME/etc/hadoop" ]; then
        export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
        echo "Using Hadoop config from: $HADOOP_CONF_DIR"
    else
        echo "ERROR: Hadoop configuration not found!"
        exit 1
    fi
else
    export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
fi

# Source Hadoop environment
if [ -f "$HADOOP_CONF_DIR/hadoop-env.sh" ]; then
    . "$HADOOP_CONF_DIR/hadoop-env.sh"
    echo "Sourced hadoop-env.sh"
fi

echo "HADOOP_HOME: $HADOOP_HOME"
echo "HADOOP_CONF_DIR: $HADOOP_CONF_DIR"
echo "JAVA_HOME: $JAVA_HOME"
echo "HIVE_HOME: $HIVE_HOME"

# Test Hadoop installation
echo "=== Testing Hadoop installation ==="
if hadoop version >/dev/null 2>&1; then
    echo "Hadoop command: OK"
    hadoop version | head -1
else
    echo "Hadoop command: FAILED - trying alternative approach"
    # Пробуем прямой вызов Java
    if java -cp "$HADOOP_HOME/share/hadoop/common/*" org.apache.hadoop.util.VersionInfo 2>/dev/null; then
        echo "Hadoop Java classes: OK"
    else
        echo "ERROR: Hadoop installation is broken"
        echo "Checking Hadoop directory structure:"
        ls -la $HADOOP_HOME/
        exit 1
    fi
fi

echo "Waiting for PostgreSQL on ${METASTORE_DB_HOSTNAME} to launch on 5432 ..."

# Wait for PostgreSQL
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${METASTORE_DB_HOSTNAME}/5432" 2>/dev/null; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:5432 started"
echo "Waiting for PostgreSQL to be ready..."
sleep 10

# Создаем базу данных и пользователя если нужно
echo "=== Setting up PostgreSQL database ==="
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE DATABASE IF NOT EXISTS metastore;" 2>/dev/null
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE USER IF NOT EXISTS hive WITH PASSWORD 'hive';" 2>/dev/null
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE metastore TO hive;" 2>/dev/null

echo "=== Initializing Hive Schema ==="
# Пробуем несколько подходов к инициализации схемы

# Approach 1: Use schematool with full path
if /opt/hive/bin/schematool -dbType postgres -info 2>/dev/null; then
    echo "Schema already initialized"
else
    echo "Initializing schema..."
    /opt/hive/bin/schematool -initSchema -dbType postgres -verbose
    if [ $? -ne 0 ]; then
        echo "Schema initialization failed, trying alternative method..."
        # Alternative: manual schema initialization
        export HIVE_HOME=/opt/hive
        cd $HIVE_HOME
        java -cp "lib/*:$HADOOP_HOME/share/hadoop/common/*" \
            org.apache.hadoop.hive.metastore.tools.HiveSchemaTool \
            -dbType postgres -initSchema -verbose
    fi
fi

echo "=== Starting Hive Metastore ==="
# Запускаем metastore используя прямой Java вызов если нужно
if command -v hive >/dev/null 2>&1; then
    echo "Starting with: hive --service metastore --verbose"
    exec hive --service metastore --verbose
else
    echo "Starting with direct Java call..."
    exec java -cp "$HIVE_HOME/lib/*:$HADOOP_HOME/share/hadoop/common/*:$HADOOP_HOME/share/hadoop/hdfs/*" \
        -Djavax.jdo.option.ConnectionURL=jdbc:postgresql://${METASTORE_DB_HOSTNAME}:5432/metastore \
        -Djavax.jdo.option.ConnectionDriverName=org.postgresql.Driver \
        -Djavax.jdo.option.ConnectionUserName=hive \
        -Djavax.jdo.option.ConnectionPassword=hive \
        org.apache.hadoop.hive.metastore.HiveMetaStore
fi
