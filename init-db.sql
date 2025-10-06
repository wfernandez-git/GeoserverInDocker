-- Initialize PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Set default schema
SET search_path = public;

-- Grant privileges to geoserver user
-- JDBC modules will create their own tables
GRANT ALL PRIVILEGES ON SCHEMA public TO geoserver;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO geoserver;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO geoserver;

-- Grant default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO geoserver;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO geoserver;
