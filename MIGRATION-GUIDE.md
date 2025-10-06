# GeoServer XML to Database Migration - Complete Guide

**Purpose:** Migrate GeoServer from XML-based configuration to PostgreSQL-backed catalog and security.

**Environment:**
- Source: GeoServer with XML-based catalog and security (400+ users, 300+ workspaces)
- Target: GeoServer with JDBCConfig (catalog) and JDBC User/Role Services (security)
- Database: PostgreSQL 15 with PostGIS

---

## Prerequisites

1. **Source data_dir backup** at: `C:/Temp/geoserver-data-dir/geoserver-data-dir/`
2. **Admin credentials** for testing
3. **Docker and Docker Compose** installed
4. **Python 3.11+** with psycopg2 (for security migration script)

---

## Phase 1: Initial Setup (Clean Start)

### Step 1.1: Verify Source Data

```bash
# Check source data_dir structure
ls -la "C:/Temp/geoserver-data-dir/geoserver-data-dir/"

# Expected directories:
# - workspaces/  (catalog data)
# - security/    (users, roles)
# - styles/      (style definitions)
```

**Verify:**
- [ ] Source data_dir exists and is complete
- [ ] Contains security/usergroup/default/users.xml
- [ ] Contains security/role/default/roles.xml
- [ ] Contains workspaces/ directory with XML configs

### Step 1.2: Prepare Docker Environment

Your `docker-compose.yml` should include:
- PostgreSQL 15 with PostGIS
- GeoServer 2.25.0
- Health checks for both services
- Named volumes for persistence

Your `Dockerfile` should include:
- JDBCConfig plugin (for catalog storage)
- AuthKey plugin (for API authentication)
- **DO NOT include JDBCStore plugin** (causes conflicts)

### Step 1.3: Build Fresh Docker Image

```bash
cd c:/Claude/Geoserver
docker-compose build --no-cache geoserver
```

**Verify:**
- [ ] Build completes without errors
- [ ] JDBCConfig plugin downloaded
- [ ] AuthKey plugin downloaded

---

## Phase 2: Catalog Migration (JDBCConfig)

### Step 2.1: Start PostgreSQL Only

```bash
docker-compose up -d postgis
sleep 10  # Wait for PostgreSQL to initialize
```

**Verify:**
```bash
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "SELECT version();"
```

**CRITICAL: Verify Database is Clean**

If you're re-running the migration, ensure the database doesn't contain old tables:

```bash
# Check for existing JDBCConfig tables
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "\dt public.*"
```

**Expected output:** Only `spatial_ref_sys` table (from PostGIS)

**If you see other tables (object, type, etc.), clean the database:**

```bash
# Drop and recreate public schema
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO geoserver; GRANT ALL ON SCHEMA public TO public;"

# Reinstall PostGIS
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "CREATE EXTENSION postgis;"

# Verify clean state
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "\dt public.*"
```

**Verify:**
- [ ] Only `spatial_ref_sys` table exists
- [ ] No `object`, `type`, `object_property` tables present

### Step 2.2: Copy Source Data to GeoServer Volume

**IMPORTANT:** We create the volume and copy data WITHOUT starting GeoServer yet.

```bash
# Create the volume by accessing it with alpine
docker volume create geoserver_geoserver-data

# Copy source data directly to the new volume
docker run --rm \
  -v "C:/Temp/geoserver-data-dir/geoserver-data-dir:/source:ro" \
  -v geoserver_geoserver-data:/target \
  alpine sh -c "cp -a /source/. /target/"

# Verify copy
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "ls -la /data/"
```

**Expected output:**
- security/
- workspaces/
- styles/
- global.xml
- logging.xml

### Step 2.3: Overwrite JDBCConfig Properties

**CRITICAL:** The source data may contain an old jdbcconfig.properties with `enabled=false`. Overwrite it with the correct one:

```bash
docker run --rm \
  -v "c:/Claude/Geoserver:/host:ro" \
  -v geoserver_geoserver-data:/target \
  alpine sh -c "cp /host/jdbcconfig.properties /target/jdbcconfig/"
```

**Verify the correct settings:**
```bash
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "grep 'enabled=' /data/jdbcconfig/jdbcconfig.properties"
```

**Expected:** `enabled=true`

### Step 2.4: Copy JDBCConfig Init Scripts

**CRITICAL:** The init SQL scripts must be copied from the Docker image to the volume:

```bash
docker run --rm --entrypoint="" \
  -v geoserver_geoserver-data:/target \
  geoserver-geoserver \
  sh -c "mkdir -p /target/jdbcconfig/scripts && cp /opt/geoserver/data_dir/jdbcconfig/scripts/*.sql /target/jdbcconfig/scripts/"
```

**Verify scripts copied:**
```bash
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "ls -la /data/jdbcconfig/scripts/"
```

**Expected:** `initdb.postgres.sql` and other database scripts

### Step 2.5: Start GeoServer for Catalog Import

```bash
docker-compose up -d geoserver
```

**Monitor the import** (this takes 2-5 minutes for large catalogs):

```bash
# Watch for JDBCConfig initialization
docker logs -f geoserver 2>&1 | grep -i "jdbcconfig\|import\|running catalog"
```

**Look for:**
- "Loading jdbcloader properties from jdbcconfig/jdbcconfig.properties"
- "JDBCConfig using JDBC DataSource"
- "Running catalog database init script"
- "CREATE TABLE object"
- "Initialization SQL script run sucessfully"

### Step 2.6: Verify Catalog Import

Wait 3-5 minutes after startup, then check:

```bash
# Check catalog tables created
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "\dt public.*"

# Expected tables:
# - object
# - object_property
# - type
# - property_type
# - default_object

# Check catalog data imported
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "
SELECT typename, COUNT(*)
FROM type t
JOIN object o ON t.oid = o.type_id
GROUP BY typename
ORDER BY count DESC
LIMIT 10;
"
```

**Expected results:**
- org.geoserver.catalog.LayerInfo: ~3000+
- org.geoserver.catalog.FeatureTypeInfo: ~3000+
- org.geoserver.catalog.WorkspaceInfo: ~300+
- org.geoserver.catalog.DataStoreInfo: ~400+

**Checkpoint 1:**
- [ ] Catalog tables created in PostgreSQL
- [ ] Workspace count matches source
- [ ] Layer count matches source
- [ ] GeoServer web UI accessible at http://localhost:8080/geoserver/web/

---

## Phase 3: Security Migration (JDBC User/Role Services)

### Step 3.1: Create Security Tables

```bash
docker exec -i geoserver-postgis psql -U geoserver -d geoserver << 'EOF'
-- Role tables
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

-- User tables
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

-- Group tables
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

-- Insert default roles
INSERT INTO roles (name, parent) VALUES ('ADMIN', NULL) ON CONFLICT DO NOTHING;
INSERT INTO roles (name, parent) VALUES ('GROUP_ADMIN', NULL) ON CONFLICT DO NOTHING;
INSERT INTO roles (name, parent) VALUES ('AUTHENTICATED', NULL) ON CONFLICT DO NOTHING;
EOF
```

**Verify:**
```bash
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "\dt" | grep -E "users|roles|groups"
```

### Step 3.2: Extract XML Security Files

```bash
# Copy users.xml and roles.xml from container
docker run --rm \
  -v geoserver_geoserver-data:/data \
  -v "c:/Claude/Geoserver:/host" \
  alpine sh -c "
    cp /data/security/usergroup/default/users.xml /host/ && \
    cp /data/security/role/default/roles.xml /host/ && \
    echo 'XML files copied'
  "
```

### Step 3.3: Run Migration Script

**The migration script** (`migrate-security.py`) parses XML and inserts into PostgreSQL.

```bash
# Run migration in Docker container with Python
docker run --rm \
  --network geoserver_geoserver-network \
  -v "//c/Claude/Geoserver:/workspace" \
  -w //workspace \
  python:3.11-slim sh -c "
    pip install -q psycopg2-binary && \
    python migrate-security.py users.xml roles.xml
  "
```

**Expected output:**
```
📖 Parsing users.xml...
📖 Parsing roles.xml...

📦 Found:
   421 users
   421 user properties
   423 unique roles
   424 user-role assignments

🔄 Migrating to database...
Inserting 423 roles...
Inserting 421 users...
Inserting 421 user properties...
Inserting 424 user-role assignments...
✅ Migration completed successfully!

📊 Database Summary:
   Users: 421
   Roles: 424
   User-Role Assignments: 424
   User Properties: 421
```

### Step 3.4: Verify Security Data

```bash
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "
SELECT
  (SELECT COUNT(*) FROM users) as users,
  (SELECT COUNT(*) FROM roles) as roles,
  (SELECT COUNT(*) FROM user_roles) as assignments,
  (SELECT COUNT(*) FROM user_props WHERE propname='UUID') as authkeys;
"
```

**Expected:**
- Users: 421
- Roles: 424
- Assignments: 424
- AuthKeys: 421

**Checkpoint 2:**
- [ ] Security tables created
- [ ] All users migrated with passwords
- [ ] All roles migrated
- [ ] AuthKey UUIDs preserved

---

## Phase 4: Configure JDBC Security Services

**CRITICAL:** This must be done carefully in the correct order.

### Step 4.1: Access GeoServer Web UI

1. Open browser: http://localhost:8080/geoserver/web/
2. Login with XML admin credentials from source system
3. Navigate to: **Security** → **Users, Groups, and Roles**

### Step 4.2: Add JDBC User Group Service

Click **"Add new"** under "User Group Services" section:

**Configuration:**
- Name: `jdbc`
- Enabled: ✓ (checked)
- Password encryption: **Digest**
- Password policy: `default`

**JDBC Connection:**
- JDBC URL: `jdbc:postgresql://postgis:5432/geoserver`
- Driver class: `org.postgresql.Driver`
- Username: `geoserver`
- Password: `geoserver`

Click **"Test Connection"** - should succeed.
Click **"Save"**.

### Step 4.3: Add JDBC Role Service

Click **"Add new"** under "Role Services" section:

**IMPORTANT:** The administrator role dropdowns will not show any roles until the service is created. You must create the service first, then edit it to add the administrator roles.

**Initial Configuration (Step 1):**
- Name: `jdbc`
- Administrator role: Select **"Choose One"** (leave empty)
- Group administrator role: Select **"Choose One"** (leave empty)

**JDBC Connection:**
- JDBC URL: `jdbc:postgresql://postgis:5432/geoserver`
- Driver class: `org.postgresql.Driver`
- Username: `geoserver`
- Password: `geoserver`

Click **"Test Connection"** - should succeed.
Click **"Save"**.

**Configure Administrator Roles (Step 2):**

After saving, immediately click on the **`jdbc`** role service to edit it again:

- Administrator role: Select **`ADMIN`** (now available in dropdown)
- Group administrator role: Select **`GROUP_ADMIN`** (now available in dropdown)

Click **"Save"** again.

This two-step process is necessary because the role dropdowns are populated from the service itself, which doesn't exist until after the first save.

### Step 4.4: DO NOT Delete Default Services

**IMPORTANT:** Keep the `default` XML user and role services as backup!

The JDBC services will be used by default if they're listed first, but the XML services provide a fallback if database connection fails.

### Step 4.5: Configure Authentication Provider

Go to **Security** → **Authentication**

Find **"default"** authentication provider, click to edit:
- User Group Service: Select **`default`** (keep XML for admin access)
- Click **Save**

**Why?** We keep the XML service for administrative access. Production users will use a separate authentication mechanism or you can switch this to `jdbc` after thorough testing.

### Step 4.6: Update AuthKey Filter (If Using)

Go to **Security** → **Authentication** → scroll to **Authentication Filters**

Find **"AuthKey"** filter, click to edit:
- User Group Service: Select **`jdbc`**
- Click **Save**

This allows AuthKey API authentication to use the database users.

### Step 4.7: Set Active Role Service

Go to **Security** → **Settings**

Find the **"Active role service"** dropdown:
- Select **`jdbc`**
- Click **Save**

**IMPORTANT:** This step is critical! Without setting the active role service to `jdbc`, GeoServer will continue using the default XML role service and your migrated roles won't be used.

**Checkpoint 3:**
- [ ] JDBC user service created and tested
- [ ] JDBC role service created and tested
- [ ] Active role service set to `jdbc`
- [ ] Default services kept as backup

---

## Phase 5: Testing and Verification

### Step 5.1: Verify Users in Web UI

1. Go to **Security** → **Users, Groups, and Roles**
2. Click **Services** tab
3. Under "User Group Services", click **`jdbc`**
4. You should see all 421 users listed

### Step 5.2: Verify Roles in Web UI

1. Still in **Users, Groups, and Roles**
2. Click **Services** tab
3. Under "Role Services", click **`jdbc`**
4. You should see all 424 roles listed

### Step 5.3: Test User Authentication

**Method 1: Web UI Login**

1. Logout of GeoServer
2. Login with a production user account (one of the migrated users)
3. Should successfully authenticate

**Method 2: Test Layer Access**

After logging in as a production user, access the Layer Preview page:

**Expected:** User should see the layers they have access to

**Method 3: REST API (Optional - Requires Admin Role)**

```bash
# Test with admin user
curl -u "geoserver_admin:PASSWORD" http://localhost:8080/geoserver/rest/about/version.json
```

**Expected:** JSON response with GeoServer version info

**Note:** Regular users may not have access to admin REST endpoints. They can still authenticate but will get 401/403 for endpoints they don't have permissions for.

### Step 5.4: Final Database Verification

```bash
# Complete summary
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "
SELECT 'Catalog Objects' as category, COUNT(*)::text as count FROM object
UNION ALL
SELECT 'Workspaces', COUNT(*)::text FROM object o JOIN type t ON o.type_id=t.oid WHERE t.typename='org.geoserver.catalog.WorkspaceInfo'
UNION ALL
SELECT 'Layers', COUNT(*)::text FROM object o JOIN type t ON o.type_id=t.oid WHERE t.typename='org.geoserver.catalog.LayerInfo'
UNION ALL
SELECT 'Users', COUNT(*)::text FROM users
UNION ALL
SELECT 'Roles', COUNT(*)::text FROM roles
UNION ALL
SELECT 'User-Role Assignments', COUNT(*)::text FROM user_roles
UNION ALL
SELECT 'AuthKey UUIDs', COUNT(*)::text FROM user_props WHERE propname='UUID';
"
```

**Checkpoint 4:**
- [ ] All users visible in JDBC service
- [ ] All roles visible in JDBC service
- [ ] Authentication works for test users
- [ ] Database counts match source data

---

## Phase 6: Post-Migration Cleanup

### Step 6.1: Disable Import After Successful Migration

**Why?** The `import=true` flag should only run once. After migration, set to `false`.

GeoServer usually does this automatically, but verify:

```bash
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "cat /data/jdbcconfig/jdbcconfig.properties | grep import"
```

If still `true`, update:

```bash
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "
sed -i 's/import=true/import=false/g' /data/jdbcconfig/jdbcconfig.properties
"

# Restart GeoServer
docker-compose restart geoserver
```

### Step 6.2: Create Database Backup

```bash
# Backup PostgreSQL database
docker exec geoserver-postgis pg_dump -U geoserver geoserver > geoserver-migrated-$(date +%Y%m%d).sql
```

### Step 6.3: Document Credentials

Create a secure record of:
- Database connection details
- Admin user credentials
- Any service account credentials
- AuthKey UUIDs for service accounts

---

## Troubleshooting Guide

### Issue: "Failed login" even with correct password

**Possible causes:**
1. Password encoder mismatch (Digest vs Plain)
2. Authentication provider pointing to wrong service
3. User exists in XML but not in database

**Solution:**
```bash
# Check if user exists in database
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "
SELECT name, LEFT(password, 20) as pwd_preview, enabled
FROM users
WHERE name='username_here';
"

# Check password encoder configuration
# In Web UI: Security → Users, Groups, Roles → Services → jdbc (edit)
# Verify "Password encryption" is set to "Digest"
```

### Issue: "Unknown user/group service: default"

**Cause:** A filter or auth provider is referencing deleted `default` service

**Solution:**
```bash
# Search for references to default service
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "
find /data/security -name '*.xml' -exec grep -l 'default' {} \;
"

# Common culprits:
# - /data/security/filter/AuthKey/config.xml
# - /data/security/auth/default/config.xml

# Update to use 'jdbc' instead
```

### Issue: Catalog not importing

**Symptoms:** Empty or missing workspaces/layers

**Check:**
```bash
# Verify import flag was set
docker run --rm -v geoserver_geoserver-data:/data alpine cat /data/jdbcconfig/jdbcconfig.properties

# Check logs for import process
docker logs geoserver 2>&1 | grep -i "import\|catalog"
```

**Solution:** Ensure `import=true` and `initdb=true` are set before first startup with source data_dir.

### Issue: GeoServer won't start

**Check logs:**
```bash
docker logs geoserver 2>&1 | grep -i "error\|exception\|failed"
```

**Common causes:**
- Database not ready (wait 30 seconds after starting postgis)
- Port 8080 already in use
- JDBCConfig tables already exist but import=true (conflict)

---

## Rollback Procedure

If migration fails and you need to rollback:

### Rollback Step 1: Stop containers
```bash
docker-compose down
```

### Rollback Step 2: Remove volumes
```bash
docker volume rm geoserver_geoserver-data geoserver_postgis-data
```

### Rollback Step 3: Restore original data_dir
```bash
# Start fresh
docker-compose up -d

# Copy original data back
docker run --rm \
  -v "C:/Temp/geoserver-data-dir/geoserver-data-dir:/source:ro" \
  -v geoserver_geoserver-data:/target \
  alpine sh -c "rm -rf /target/* && cp -a /source/. /target/"
```

### Rollback Step 4: Disable JDBC modules
```bash
# Disable JDBCConfig
docker run --rm -v geoserver_geoserver-data:/data alpine sh -c "
echo 'enabled=false' > /data/jdbcconfig/jdbcconfig.properties
"

docker-compose restart geoserver
```

---

## Success Criteria

Migration is successful when ALL of the following are true:

- [ ] **Catalog:** 300+ workspaces visible in GeoServer web UI
- [ ] **Catalog:** 3000+ layers visible and functional
- [ ] **Catalog:** Database contains all workspace/layer data
- [ ] **Security:** 421 users exist in PostgreSQL
- [ ] **Security:** 424 roles exist in PostgreSQL
- [ ] **Security:** Test user can authenticate via web UI
- [ ] **Security:** Test user can authenticate via REST API
- [ ] **AuthKey:** API authentication works with UUIDs
- [ ] **Performance:** GeoServer starts within 2-3 minutes
- [ ] **Stability:** No errors in GeoServer logs
- [ ] **Backup:** Database backup created and tested

---

## Maintenance

### Daily Operations

**View users:**
```sql
SELECT name, enabled FROM users ORDER BY name;
```

**Add new user:**
```sql
INSERT INTO users (name, password, enabled) VALUES ('newuser', 'digest1:hash', '1');
INSERT INTO user_roles (username, rolename) VALUES ('newuser', 'AUTHENTICATED');
```

**Disable user:**
```sql
UPDATE users SET enabled='0' WHERE name='username';
```

### Backup Schedule

```bash
# Daily backup script
docker exec geoserver-postgis pg_dump -U geoserver geoserver | \
  gzip > /backups/geoserver-$(date +%Y%m%d).sql.gz
```

### Monitoring

**Check database connections:**
```bash
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "
SELECT count(*) as active_connections
FROM pg_stat_activity
WHERE datname='geoserver';
"
```

**Check catalog object count:**
```bash
docker exec geoserver-postgis psql -U geoserver -d geoserver -c "
SELECT COUNT(*) FROM object;
"
```

---

## Support Resources

- **GeoServer JDBC Security:** https://docs.geoserver.org/latest/en/user/security/usergrouprole/jdbc.html
- **JDBCConfig:** https://docs.geoserver.org/main/en/user/community/jdbcconfig/
- **PostgreSQL:** https://www.postgresql.org/docs/
- **Docker Compose:** https://docs.docker.com/compose/

---

**Migration Guide Version:** 1.0
**Last Updated:** October 3, 2025
**Tested On:** GeoServer 2.25.0, PostgreSQL 15, Docker 24.x
