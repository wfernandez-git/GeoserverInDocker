# GeoServer with JDBC Security and PostGIS

Docker setup for GeoServer 2.24.5 with JDBC-backed user/role management in PostgreSQL/PostGIS.

## Features

- 🗺️ **GeoServer 2.24.5** with Tomcat 9
- 🔐 **JDBC Security** - Users and roles stored in PostgreSQL
- 🔑 **AuthKey Extension** - API authentication support
- 🗄️ **PostGIS 15-3.3** - Spatial database backend
- 🐳 **Docker Compose** - Single command deployment
- ✅ **Pre-configured** - Database tables and admin user ready

## Quick Start

```bash
# Start services
docker-compose up -d

# Access GeoServer
open http://localhost:8080/geoserver
# Login: admin / geoserver
```

## What's Included

- **GeoServer** on port 8080
- **PostGIS** on port 5432
- **8 security tables** pre-created in `public` schema
- **Admin user** (`admin`/`geoserver`) in database
- **3 default roles** (ADMIN, GROUP_ADMIN, AUTHENTICATED)
- **AuthKey extension** installed
- **JDBC Store plugin** installed

## Setup Instructions

See [SETUP.md](SETUP.md) for complete step-by-step instructions to:

1. Create JDBC User Group Service (5 minutes)
2. Create JDBC Role Service (5 minutes)
3. Configure AuthKey authentication (optional)

## Architecture

```
┌─────────────────────────────────┐
│  GeoServer (Port 8080)          │
│  - AuthKey Extension            │
│  - JDBC Store Plugin            │
└───────────┬─────────────────────┘
            │ JDBC Connection
┌───────────▼─────────────────────┐
│  PostGIS (Port 5432)            │
│  - 8 security tables            │
│  - Admin user pre-created       │
└─────────────────────────────────┘
```

## Database Connection

From **pgAdmin** or other PostgreSQL clients:

- **Host**: `localhost`
- **Port**: `5432`
- **Database**: `geoserver`
- **Username**: `geoserver`
- **Password**: `geoserver`

## Files

- `docker-compose.yml` - Service orchestration
- `Dockerfile` - Custom GeoServer image
- `init-db.sql` - Database initialization
- `entrypoint.sh` - GeoServer startup script
- `SETUP.md` - Detailed setup instructions

## Management

```bash
# View logs
docker logs geoserver
docker logs geoserver-postgis

# Restart services
docker-compose restart

# Stop services
docker-compose down

# Complete reset (deletes all data!)
docker-compose down -v
docker-compose up -d
```

## Requirements

- Docker
- Docker Compose

## Database Schema

All tables in `public` schema:

**User Management:**
- `users` - User accounts (name, password, enabled)
- `user_props` - User properties (for AuthKey UUIDs)
- `user_roles` - User-to-role assignments

**Group Management:**
- `groups` - User groups
- `group_members` - Group memberships
- `group_roles` - Group-to-role assignments

**Role Management:**
- `roles` - Available roles
- `role_props` - Role properties

## Notes

- Database schema matches GeoServer's default DML queries
- Users table uses `name` column (not `username`) per GeoServer convention
- `enabled` column is CHAR(1) with values '1'/'0'
- Admin password stored in plain text format `plain:geoserver` for GeoServer compatibility

## Support

- **GeoServer Docs**: https://docs.geoserver.org/
- **JDBC Security**: https://docs.geoserver.org/latest/en/user/security/usergrouprole/jdbc.html
- **AuthKey**: https://docs.geoserver.org/latest/en/user/extensions/authkey/index.html

## License

This is a configuration project. GeoServer and PostGIS retain their respective licenses.
