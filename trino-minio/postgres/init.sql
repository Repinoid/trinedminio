-- Create metastore database if it doesn't exist
SELECT 'CREATE DATABASE metastore_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metastore_db')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE metastore_db TO admin;
