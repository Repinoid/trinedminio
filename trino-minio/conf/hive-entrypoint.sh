#!/bin/sh

# Set environment variables
export HADOOP_HOME=/opt/hadoop
export JAVA_HOME=/usr/local/openjdk-8
export METASTORE_DB_HOSTNAME=${METASTORE_DB_HOSTNAME:-localhost}
export HIVE_HOME=/opt/hive

export PATH=$HADOOP_HOME/bin:$JAVA_HOME/bin:$HIVE_HOME/bin:$PATH

# Add PostgreSQL JDBC driver to classpath
export POSTGRES_JDBC_JAR="/opt/hadoop-3.2.0/share/hadoop/common/lib/postgresql-jdbc.jar"
export CLASSPATH="$POSTGRES_JDBC_JAR:$CLASSPATH"
export HADOOP_CLASSPATH="$POSTGRES_JDBC_JAR:$HADOOP_CLASSPATH"

echo "=== Environment Setup ==="
echo "HADOOP_HOME: $HADOOP_HOME"
echo "JAVA_HOME: $JAVA_HOME"
echo "HIVE_HOME: $HIVE_HOME"
echo "POSTGRES_JDBC_JAR: $POSTGRES_JDBC_JAR"

# Wait for PostgreSQL
echo "Waiting for PostgreSQL on ${METASTORE_DB_HOSTNAME} to launch on 5432 ..."
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${METASTORE_DB_HOSTNAME}/5432" 2>/dev/null; do
  sleep 1
done

echo "Database on ${METASTORE_DB_HOSTNAME}:5432 started"
echo "Waiting for PostgreSQL to be ready..."
sleep 10

echo "=== Setting up PostgreSQL database ==="
# Create database and user with proper password
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE DATABASE IF NOT EXISTS metastore;" 2>/dev/null || true
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "CREATE USER IF NOT EXISTS hive WITH PASSWORD 'hive';" 2>/dev/null || true
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE metastore TO hive;" 2>/dev/null || true
PGPASSWORD=postgres psql -h $METASTORE_DB_HOSTNAME -U postgres -c "ALTER USER hive WITH PASSWORD 'hive';" 2>/dev/null || true

echo "=== Creating Hive configuration ==="
# Create hive-site.xml with proper PostgreSQL configuration
cat > $HIVE_HOME/conf/hive-site.xml << EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:postgresql://${METASTORE_DB_HOSTNAME}:5432/metastore</value>
    <description>PostgreSQL JDBC connection URL</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>org.postgresql.Driver</value>
    <description>Driver class name</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>hive</value>
    <description>Username</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>hive</value>
    <description>Password</description>
  </property>
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>/user/hive/warehouse</value>
    <description>HDFS warehouse directory</description>
  </property>
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://0.0.0.0:9083</value>
    <description>Metastore URIs</description>
  </property>
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
    <description>Disable schema verification</description>
  </property>
  <property>
    <name>datanucleus.autoCreateSchema</name>
    <value>true</value>
  </property>
  <property>
    <name>datanucleus.fixedDatastore</name>
    <value>false</value>
  </property>
  <property>
    <name>datanucleus.autoCreateTables</name>
    <value>true</value>
  </property>
</configuration>
EOF
echo "Created hive-site.xml"

echo "=== Manual Schema Initialization ==="
# Initialize schema manually since schematool has issues
PGPASSWORD=hive psql -h $METASTORE_DB_HOSTNAME -U hive -d metastore -c "
CREATE TABLE IF NOT EXISTS VERSION (
    VER_ID BIGINT NOT NULL,
    SCHEMA_VERSION VARCHAR(127) NOT NULL,
    VERSION_COMMENT VARCHAR(255),
    PRIMARY KEY (VER_ID)
);
INSERT INTO VERSION (VER_ID, SCHEMA_VERSION, VERSION_COMMENT) 
VALUES (1, '4.0.0-beta-1', 'Hive release version 4.0.0-beta-1')
ON CONFLICT (VER_ID) DO NOTHING;
" 2>/dev/null || echo "Manual schema initialization attempted"

echo "=== Starting Hive Metastore ==="
# Start metastore with explicit classpath including PostgreSQL driver
exec java -cp "$HIVE_HOME/lib/*:$POSTGRES_JDBC_JAR:$HADOOP_HOME/share/hadoop/common/*" \
    -Djavax.jdo.option.ConnectionURL="jdbc:postgresql://${METASTORE_DB_HOSTNAME}:5432/metastore" \
    -Djavax.jdo.option.ConnectionDriverName="org.postgresql.Driver" \
    -Djavax.jdo.option.ConnectionUserName="hive" \
    -Djavax.jdo.option.ConnectionPassword="hive" \
    -Dhive.metastore.uris="thrift://0.0.0.0:9083" \
    -Dhive.metastore.schema.verification="false" \
    org.apache.hadoop.hive.metastore.HiveMetaStore
    