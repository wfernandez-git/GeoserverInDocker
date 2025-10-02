# Project Context for AI Assistants and Developers

This document explains the architecture, design decisions, and lessons learned building this GeoServer JDBC Docker deployment.

## Project Goal

Create a Docker-based GeoServer deployment where users and roles are stored in PostgreSQL instead of XML files, with minimal manual configuration required.

## Architecture Decisions

### Why PostgreSQL for User Management?

**Problem**: GeoServer's default user/role storage uses XML files, which:
- Don't scale well for many users
- Are difficult to manage programmatically
- Can't be shared across multiple GeoServer instances
- Lack audit trails and transaction safety

**Solution**: JDBC-backed security using PostgreSQL provides:
- Centralized user management
- SQL-based user administration
- Multi-instance support
- Database-level security and auditing

### Why Manual JDBC Service Configuration?

**Initial Approach**: We tried fully automating JDBC service configuration by:
1. Pre-creating XML configuration files
2. Copying them during Docker build
3. Letting GeoServer discover them on startup

**Result**: Multiple failures:
- `ClassCastException` - Wrong XML root element types
- `NullPointerException` - GeoServer migration logic conflicts
- Startup crashes when pre-configurations existed
- Port binding issues with start/stop/restart approach

**Final Approach**: Let users create services via web UI because:
- GeoServer's initialization is complex and version-specific
- Web UI validates configurations properly
- Manual setup takes only 5-10 minutes
- It's more reliable across GeoServer versions
- Users understand their configuration better

### Why `public` Schema Instead of Custom Schema?

**Initial Design**: Created `security` schema for organization:
```sql
CREATE SCHEMA security;
CREATE TABLE security.users ...
```

**Problem**: GeoServer's default DML queries don't include schema prefixes:
```sql
SELECT name, password FROM users  -- no schema prefix!
```

**Solutions Considered**:
1. ❌ Modify PostgreSQL search_path - fragile, affects all queries
2. ❌ Customize all DML queries - complex, error-prone
3. ✅ Use `public` schema - matches GeoServer's defaults

**Lesson**: Work with framework conventions, not against them.

### Why `users.name` Instead of `users.username`?

**Discovery**: GeoServer's default DML uses `name` as the primary key:
```sql
-- GeoServer's default query
SELECT name, password, enabled FROM users WHERE name = ?
```

**Initial Schema**:
```sql
CREATE TABLE users (
    username VARCHAR(128) PRIMARY KEY,  -- ❌ Wrong!
    ...
)
```

**Corrected Schema**:
```sql
CREATE TABLE users (
    name VARCHAR(128) PRIMARY KEY,      -- ✅ Matches GeoServer
    ...
)
```

**Why This Matters**: The `user_props` table still uses `username` to reference users:
```sql
CREATE TABLE user_props (
    username VARCHAR(128) REFERENCES users(name),  -- Different names!
    ...
)
```

This is GeoServer's convention - we must follow it.

### Why CHAR(1) for `enabled` Column?

**GeoServer Expectation**: The default DDL creates:
```sql
enabled char(1) not null
```

With values `'1'` (enabled) or `'0'` (disabled).

**Initial Attempt**: Used PostgreSQL BOOLEAN:
```sql
enabled BOOLEAN NOT NULL DEFAULT TRUE  -- ❌ Type mismatch
```

**Problem**: GeoServer's queries expected character values, causing type conversion issues.

**Solution**: Match GeoServer's exact type:
```sql
enabled CHAR(1) NOT NULL DEFAULT '1'   -- ✅ Works perfectly
```

## Extension Management

### AuthKey Extension

**Purpose**: Stateless API authentication using unique keys per user.

**Installation**: Downloaded from GeoServer build server during Docker build:
```dockerfile
RUN wget https://build.geoserver.org/geoserver/2.24.x/ext-latest/
         geoserver-2.24-SNAPSHOT-authkey-plugin.zip
```

**Why Not Auto-Configure**: Same reasons as JDBC services - causes ClassNotFoundException warnings and complexity.

**Usage**: Users add UUID property to user accounts, then authenticate with:
```
http://localhost:8080/geoserver/wms?UUID=user-key-here&...
```

### JDBC Store Plugin

**Purpose**: Enables database-backed user/role storage.

**Installation**: Community module, downloaded during build:
```dockerfile
RUN wget https://build.geoserver.org/geoserver/2.24.x/community-latest/
         geoserver-2.24-SNAPSHOT-jdbcstore-plugin.zip
```

**Status**: Installed and available, activated via web UI configuration.

## Database Schema Design

### User Management Tables

```sql
users           -- User accounts (name, password, enabled)
  └─ user_props    -- User properties like AuthKey UUIDs
  └─ user_roles    -- Direct role assignments
  └─ group_members -- Group memberships
```

### Group Management Tables

```sql
groups          -- User groups (name, enabled)
  └─ group_members -- Which users belong to groups
  └─ group_roles   -- Roles inherited from groups
```

### Role Management Tables

```sql
roles           -- Role definitions (name, parent for hierarchy)
  └─ role_props    -- Role properties
  └─ user_roles    -- Direct user assignments
  └─ group_roles   -- Group-based assignments
```

**Key Design**: Flexible RBAC (Role-Based Access Control) with:
- Direct user-to-role assignment
- Group-based role inheritance
- Role hierarchy via parent relationships
- Properties for extensibility

## Common Pitfalls & Solutions

### Pitfall 1: Incomplete DDL Configuration

**Symptom**: "column 'name' does not exist" error when accessing users.

**Cause**: Only table names filled in, not column attribute mappings.

**Solution**: Fill in ALL DDL fields when creating JDBC services:
- Users table: `users`
- User name attribute: `name`
- User password attribute: `password`
- User enabled attribute: `enabled`
- ... (all other attributes)

### Pitfall 2: Using `-v` Flag Unexpectedly

**Command**: `docker-compose down -v`

**Effect**: Deletes ALL volumes including:
- PostgreSQL data (❌ data loss)
- GeoServer data directory (❌ JDBC service configs lost)

**When to Use**: Only for complete reset during development.

**Safe Alternative**: `docker-compose down` (keeps volumes).

### Pitfall 3: Expecting Immediate Configuration

**Expectation**: JDBC services should work immediately after container starts.

**Reality**: Manual web UI configuration is required (5-10 minutes).

**Why**: Automated configuration proved unreliable across GeoServer versions and scenarios.

## Testing Strategy

### Verification Checklist

After `docker-compose up --build`:

1. **Containers healthy**:
   ```bash
   docker ps  # Both should show "healthy"
   ```

2. **Database tables created**:
   ```bash
   docker exec geoserver-postgis psql -U geoserver -d geoserver -c "\dt public.*"
   # Should show 8 security tables + spatial_ref_sys
   ```

3. **Admin user exists**:
   ```bash
   docker exec geoserver-postgis psql -U geoserver -d geoserver \
     -c "SELECT name, enabled FROM users;"
   # Should show: admin | 1
   ```

4. **GeoServer accessible**:
   ```bash
   curl -f http://localhost:8080/geoserver/web/
   # Should return 302 redirect (success)
   ```

5. **Manual configuration**:
   - Follow SETUP.md to create JDBC services
   - Verify admin user appears in Users tab
   - Verify roles appear in Roles tab

## Development Timeline & Evolution

### Phase 1: Initial Design (Automated Everything)
- Created security schema
- Pre-configured JDBC services
- Expected zero manual setup
- **Result**: Startup failures, crashes

### Phase 2: Schema Fixes
- Moved to public schema
- Fixed column names (username → name)
- Fixed data types (BOOLEAN → CHAR(1))
- **Result**: Database working, but services still problematic

### Phase 3: Simplified Approach
- Removed automatic service configuration
- Simplified entrypoint (single-pass startup)
- Documented manual steps clearly
- **Result**: Reliable, reproducible setup

### Key Insight

**Principle**: Automate infrastructure, document configuration.

- ✅ Automate: Docker images, database schema, dependencies
- 📝 Document: Application-level configuration requiring domain knowledge

## File Purposes

| File | Purpose | Audience |
|------|---------|----------|
| `README.md` | Quick start, overview | End users |
| `SETUP.md` | Step-by-step manual config | End users, ops |
| `CLAUDE.md` | Architecture & decisions | Developers, AI |
| `.clinerules` | Technical implementation | AI assistants |
| `docker-compose.yml` | Service orchestration | Docker |
| `Dockerfile` | GeoServer image build | Docker |
| `init-db.sql` | Database initialization | PostgreSQL |
| `entrypoint.sh` | Startup coordination | Container runtime |

## Future Improvements

### Potential Enhancements

1. **Health Check Scripts**: More detailed health verification beyond HTTP 200
2. **Backup/Restore Scripts**: Automated database backup procedures
3. **Multi-Instance Support**: Load balancer configuration examples
4. **Monitoring Integration**: Prometheus metrics, logging aggregation
5. **SSL/TLS**: HTTPS configuration for production deployments

### What NOT to Add

1. ❌ **Automated JDBC Configuration**: Learned it's unreliable
2. ❌ **Custom DML Queries**: Maintenance burden, version compatibility issues
3. ❌ **Non-standard Schema Names**: Breaks GeoServer conventions

## Questions for Future Maintainers

**Q: Why not use environment variables for JDBC connection strings?**
A: GeoServer JDBC services need to be configured through web UI or REST API. Environment variables don't integrate with GeoServer's security subsystem initialization.

**Q: Can we upgrade to newer GeoServer versions?**
A: Yes, but verify:
- Extension compatibility (check build.geoserver.org)
- Default DML queries haven't changed
- Test with clean volumes first

**Q: Why not use JNDI datasources?**
A: Adds complexity without significant benefit for this use case. Direct JDBC connections are simpler and equally functional.

**Q: Can we use MySQL instead of PostgreSQL?**
A: Yes, but:
- Change driver in JDBC configuration
- Adjust init-db.sql syntax (MySQL vs PostgreSQL)
- Test spatial extensions if needed
- Update connection URLs

## Resources

- [GeoServer JDBC Security Docs](https://docs.geoserver.org/latest/en/user/security/usergrouprole/jdbc.html)
- [GeoServer AuthKey Extension](https://docs.geoserver.org/latest/en/user/extensions/authkey/index.html)
- [PostGIS Documentation](https://postgis.net/documentation/)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)

---

**For AI Assistants**: This project prioritizes reliability over automation. Manual configuration via web UI is intentional and should not be "fixed" with automated XML configuration.
