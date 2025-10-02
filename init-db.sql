-- Initialize PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Use public schema for GeoServer JDBC Security tables
-- GeoServer's default queries expect tables in the public schema
SET search_path = public;

-- ============================================================
-- JDBC Role Service Tables
-- ============================================================

CREATE TABLE IF NOT EXISTS roles (
    name VARCHAR(128) PRIMARY KEY,
    parent VARCHAR(128)
);

CREATE TABLE IF NOT EXISTS role_props (
    rolename VARCHAR(128) NOT NULL,
    propname VARCHAR(128) NOT NULL,
    propvalue VARCHAR(2048),
    PRIMARY KEY (rolename, propname),
    FOREIGN KEY (rolename) REFERENCES roles(name) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_roles (
    username VARCHAR(128) NOT NULL,
    rolename VARCHAR(128) NOT NULL,
    PRIMARY KEY (username, rolename),
    FOREIGN KEY (rolename) REFERENCES roles(name) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS group_roles (
    groupname VARCHAR(128) NOT NULL,
    rolename VARCHAR(128) NOT NULL,
    PRIMARY KEY (groupname, rolename),
    FOREIGN KEY (rolename) REFERENCES roles(name) ON DELETE CASCADE
);

-- ============================================================
-- JDBC User Group Service Tables
-- ============================================================
-- Note: Using 'name' instead of 'username' to match GeoServer's default DML queries

CREATE TABLE IF NOT EXISTS users (
    name VARCHAR(128) PRIMARY KEY,
    password VARCHAR(254),
    enabled CHAR(1) NOT NULL DEFAULT '1'
);

CREATE TABLE IF NOT EXISTS user_props (
    username VARCHAR(128) NOT NULL,
    propname VARCHAR(128) NOT NULL,
    propvalue VARCHAR(2048),
    PRIMARY KEY (username, propname),
    FOREIGN KEY (username) REFERENCES users(name) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS groups (
    name VARCHAR(128) PRIMARY KEY,
    enabled CHAR(1) NOT NULL DEFAULT '1'
);

CREATE TABLE IF NOT EXISTS group_members (
    groupname VARCHAR(128) NOT NULL,
    username VARCHAR(128) NOT NULL,
    PRIMARY KEY (groupname, username),
    FOREIGN KEY (groupname) REFERENCES groups(name) ON DELETE CASCADE,
    FOREIGN KEY (username) REFERENCES users(name) ON DELETE CASCADE
);

-- ============================================================
-- Insert Default Roles
-- ============================================================

INSERT INTO roles (name, parent) VALUES ('ADMIN', NULL) ON CONFLICT DO NOTHING;
INSERT INTO roles (name, parent) VALUES ('GROUP_ADMIN', NULL) ON CONFLICT DO NOTHING;
INSERT INTO roles (name, parent) VALUES ('AUTHENTICATED', NULL) ON CONFLICT DO NOTHING;

-- ============================================================
-- Insert Default Admin User
-- ============================================================
-- Password: geoserver (plain:geoserver format for GeoServer)
-- Note: enabled='1' for CHAR(1) column (1=enabled, 0=disabled)

INSERT INTO users (name, password, enabled)
VALUES ('admin', 'plain:geoserver', '1')
ON CONFLICT DO NOTHING;

-- Assign ADMIN role to admin user
INSERT INTO user_roles (username, rolename)
VALUES ('admin', 'ADMIN')
ON CONFLICT DO NOTHING;

-- ============================================================
-- Grant privileges on tables
-- ============================================================

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO geoserver;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO geoserver;
