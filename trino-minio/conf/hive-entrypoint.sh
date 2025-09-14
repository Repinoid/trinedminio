#!/bin/sh

# hive-metastore:
#     image: 'bitsondatadev/hive-metastore:latest'
#       ...
#     volumes:
#       - ./conf/metastore-site.xml:/opt/apache-hive-metastore-3.0.0-bin/conf/metastore-site.xml:ro
#       - ./mariam/mariadb-java-client-3.5.6.jar:/opt/hadoop-3.2.0/share/hadoop/common/lib/mariadb-java-client-3.5.6.jar:ro
#       - ./conf/hive-entrypoint.sh:/hive-entrypoint.sh:ro
    #  environment:
    #    METASTORE_DB_HOSTNAME: mariadb
    #    DB_PORT: 3306

#  указывает путь к установленному Hadoop.
export HADOOP_HOME=/opt/hadoop-3.2.0

# задает класс-путь для Hadoop, включающий библиотеки AWS и другие необходимые JAR-файлы.
export HADOOP_CLASSPATH="
${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk-bundle-1.11.375.jar:\
${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws-3.2.0.jar:\
${HADOOP_HOME}/share/hadoop/common/lib/*"

# указывает на установленную версию Java.
export JAVA_HOME=/usr/local/openjdk-8
# задает имя хоста базы данных метастора, по умолчанию localhost , если переменная не задана.
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}

echo "Waiting for database on ${METASTORE_DB_HOSTNAME} to launch on 3306 ..."

# Ожидаем доступности MariaDB
# -z означает "сканировать только наличие открытого порта без отправки данных".
# команда проверяет, слушает ли на этом порту удаленный сервер.
while ! nc -z ${METASTORE_DB_HOSTNAME} 3306; do
  sleep 1
done

echo "=== Searching for available services ==="
find /opt/hive -name "*service*" -type f 2>/dev/null
find /opt/hive -name "*start*" -type f 2>/dev/null
ls -la /opt/hive/bin/ | grep -E '(meta|service|start)'
echo "=== END Searching for available services ==="

echo "=== Checking available JAR files ==="
ls -la /opt/hive/lib/ | grep -E '(meta|hive|jdo)'
ls -la /opt/hadoop-3.2.0/share/hadoop/common/lib/ | grep -E '(mysql|mariadb)'
echo "=== JAR check completed ==="

echo "Database on ${METASTORE_DB_HOSTNAME}:3306 started"

# Проверяем, инициализирована ли уже схема
echo "Checking if schema is already initialized..."
if /opt/hive/bin/schematool -dbType mysql -info; then
    echo "Schema is already initialized, skipping initSchema"
else
    echo "Initializing apache hive metastore schema on ${METASTORE_DB_HOSTNAME}:3306"
    # Используем флаг -ifNotExists для избежания ошибок с существующими таблицами
    /opt/hive/bin/schematool -initSchema -dbType mysql -ifNotExists
    
    # Проверяем успешность инициализации
    if [ $? -eq 0 ]; then
        echo "Schema initialized successfully"
    else
        echo "Schema initialization may have had issues, but continuing..."
    fi
fi

echo "Starting Metastore Server"
/opt/apache-hive-metastore-3.0.0-bin/bin/start-metastore

