# GeoServer with JDBC Security Setup

## Quick Start

```bash
docker-compose up -d
```

## Services

- **GeoServer**: http://localhost:8080/geoserver
  - Username: `admin`
  - Password: `geoserver`

- **PostGIS Database**: `localhost:5432`
  - Database: `geoserver`
  - Username: `geoserver`
  - Password: `geoserver`
  - Schema: `security` (contains all user/role tables)

## What's Pre-configured

✅ PostGIS database with security tables in `public` schema
✅ Default admin user (`admin`/`geoserver`) in database
✅ Default roles (ADMIN, GROUP_ADMIN, AUTHENTICATED) in database
✅ AuthKey extension installed
✅ JDBC Store plugin installed

## What Requires Manual Setup (5 minutes)

⚙️ JDBC User Group Service - needs to be created via web UI
⚙️ JDBC Role Service - needs to be created via web UI
⚙️ AuthKey filter - needs to be created and added to filter chain

## Database Tables Created

In the `security` schema:
- `users` - User accounts
- `user_props` - User properties
- `user_roles` - User-to-role assignments
- `groups` - User groups
- `group_members` - Group memberships
- `group_roles` - Group-to-role assignments
- `roles` - Available roles
- `role_props` - Role properties

## Setting Up JDBC Security (Manual)

### 1. Access GeoServer
Navigate to http://localhost:8080/geoserver and login with `admin`/`geoserver`

### 2. Create JDBC User Group Service
1. Go to: **Security** → **Users, Groups, and Roles** → **User Group Services** tab
2. Click **Add new**
3. Select **JDBC** from the list
4. Configure:
   - **Name**: `jdbc`
   - **Password encryption**: `digestPasswordEncoder`
   - **Password policy**: `default`
   - **Driver class name**: `org.postgresql.Driver`
   - **Connection URL**: `jdbc:postgresql://postgis:5432/geoserver`
   - **Username**: `geoserver`
   - **Password**: `geoserver`
   - **Create database tables**: ☐ Unchecked (tables already exist)
6. Leave **DML** section with default queries (they will auto-generate based on DDL)
7. Click **Save**
8. Click **Test Connection** - should succeed

### 3. Create JDBC Role Service
1. Go to: **Role Services** tab
2. Click **Add new**
3. Select **JDBC** from the list
4. Configure:
   - **Name**: `jdbc_roles`
   - **Administrator role**: `ADMIN`
   - **Group administrator role**: `GROUP_ADMIN`
   - **Driver class name**: `org.postgresql.Driver`
   - **Connection URL**: `jdbc:postgresql://postgis:5432/geoserver`
   - **Username**: `geoserver`
   - **Password**: `geoserver`
   - **Create database tables**: ☐ Unchecked (tables already exist)
6. Leave **DML** section with default queries (they will auto-generate based on DDL)
7. Click **Save**
8. Click **Test Connection** - should succeed
9. Set as **Active Role Service**

### 4. Verify
1. Go to **Users** tab - you should see the `admin` user from PostgreSQL
2. Go to **Roles** tab - you should see: ADMIN, GROUP_ADMIN, AUTHENTICATED

## Connect from pgAdmin

- Host: `localhost`
- Port: `5432`
- Database: `geoserver`
- Username: `geoserver`
- Password: `geoserver`

Query example:
```sql
SELECT u.username, r.name as role
FROM security.users u
JOIN security.user_roles ur ON u.username = ur.username
JOIN security.roles r ON ur.rolename = r.name;
```

## Configuring AuthKey Authentication (Manual Setup Required)

AuthKey provides stateless authentication using unique keys. Follow these steps to set it up:

### Step 1: Create AuthKey Filter

1. Go to: **Security** → **Authentication** → **Authentication Filters**
2. Click **Add new**
3. Select **AuthKey** from the list
4. Configure:
   - **Name**: `authkey`
   - **Authentication key parameter name**: `UUID`
   - **User/Group service**: Select `jdbc`
   - **Synchronize user/group service**: ☑ Check this box
5. Click **Save**

### Step 2: Add AuthKey to Filter Chain

1. Go to: **Security** → **Authentication**
2. Find the **Filter Chains** section
3. Click **Edit** on the default filter chain (usually "default" or "web")
4. In the **Available filters** list, find `authkey`
5. Move it to the **Selected filters** list
6. Position it in the chain (typically after anonymous, before other filters)
7. Click **Save**

### Step 3: Assign AuthKey (UUID) to Users

#### Option A: Through User Properties (Recommended)
1. Go to: **Security** → **Users, Groups, and Roles** → **Users**
2. Click on a user (e.g., `admin`)
3. Click **Add property**
4. Add a property:
   - **Key**: `UUID`
   - **Value**: Generate a secure random string (e.g., `a1b2c3d4e5f6...`)
5. Click **Save**

#### Option B: Directly in Database
```sql
-- Insert a UUID authkey for the admin user
INSERT INTO user_props (username, propname, propvalue)
VALUES ('admin', 'UUID', 'my-secret-key-12345')
ON CONFLICT (username, propname)
DO UPDATE SET propvalue = 'my-secret-key-12345';
```

### Step 4: Test AuthKey Authentication

```bash
# Using URL parameter with UUID
curl "http://localhost:8080/geoserver/rest/about/version.json?UUID=my-secret-key-12345"

# Using HTTP header (if configured)
curl -H "UUID: my-secret-key-12345" \
  "http://localhost:8080/geoserver/rest/about/version.json"
```

---

### AuthKey Configuration Options

**Authentication key parameter name**:
- Configured as: `UUID`
- The name of the URL parameter or HTTP header containing the key

**User/Group service to use for authentication**:
- Configured as: `jdbc`
- The user group service where users are stored

**Synchronize user/group service**:
- Configured as: ☑ Enabled
- Syncs user data from the database on each request

**Web service body response**:
- Configure how to respond to authentication failures

### Security Best Practices

1. **Use strong keys**: Generate long, random keys (32+ characters)
   ```bash
   # Generate a secure key
   openssl rand -hex 32
   ```

2. **Use HTTPS in production**: AuthKeys in URLs are visible in logs
   - Consider using HTTP headers instead of URL parameters
   - Always use HTTPS/TLS in production

3. **Rotate keys regularly**: Update keys periodically for security

4. **One key per user**: Don't share keys between users

5. **Store keys securely**: Treat them like passwords

### Common Use Cases

**Mobile Apps**:
```javascript
fetch('http://localhost:8080/geoserver/wms', {
  headers: { 'UUID': userAuthKey },
  // ... request parameters
});
```

**Python Scripts**:
```python
import requests

authkey = "my-secret-key-12345"
response = requests.get(
    "http://localhost:8080/geoserver/rest/workspaces.json",
    params={"UUID": authkey}
)
```

**WMS/WFS Clients**:
```
http://localhost:8080/geoserver/wms?
  UUID=my-secret-key-12345&
  service=WMS&
  request=GetMap&
  layers=myworkspace:mylayer&
  ...
```

### Troubleshooting AuthKey

**Problem**: Authentication fails with valid key
- **Solution**: Check that the authkey filter is in the filter chain
- **Solution**: Verify the property name matches (case-sensitive)
- **Solution**: Check user exists in the configured user group service

**Problem**: Key visible in logs
- **Solution**: Use HTTP headers instead of URL parameters
- **Solution**: Configure web server to sanitize logs

**Problem**: Need different keys for different applications
- **Solution**: Create multiple user properties (e.g., `UUID_mobile`, `UUID_web`)
- **Solution**: Configure multiple authkey filters with different parameter names

**Problem**: Users not synchronized from database
- **Solution**: Ensure "Synchronize user/group service" is checked in the AuthKey filter configuration
- **Solution**: Verify the `jdbc` user group service is properly configured and active

## Troubleshooting

If GeoServer doesn't start or the JDBC services don't appear:
1. Check logs: `docker logs geoserver`
2. Check database: `docker logs geoserver-postgis`
3. Verify tables exist: `docker exec geoserver-postgis psql -U geoserver -d geoserver -c "\dt security.*"`
4. Restart: `docker-compose restart`

## Clean Restart

To start fresh:
```bash
docker-compose down -v
docker-compose up -d
```

This will recreate all volumes and reinitialize the database.
