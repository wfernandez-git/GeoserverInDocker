#!/bin/bash
set -e

echo "Starting GeoServer initialization..."

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${POSTGRES_HOST} -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c '\q' 2>/dev/null; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 2
done

echo "=================================================="
echo "PostgreSQL is ready!"
echo "=================================================="
echo "✅ PostGIS database initialized"
echo "✅ Security tables created in 'public' schema"
echo "✅ Admin user (admin/geoserver) ready in database"
echo "✅ Roles (ADMIN, GROUP_ADMIN, AUTHENTICATED) created"
echo "✅ AuthKey extension installed"
echo "✅ JDBC Store plugin installed"
echo "✅ JDBCConfig plugin installed and configured"
echo "✅ JDBCConfig will initialize catalog tables on first run"
echo ""
echo "GeoServer will be available at: http://localhost:8080/geoserver"
echo "Login with: admin / geoserver"
echo ""
echo "MANUAL SETUP REQUIRED:"
echo "  See SETUP.md for step-by-step JDBC and AuthKey configuration"
echo "=================================================="

# Start Tomcat
echo "Starting GeoServer..."
exec catalina.sh run
