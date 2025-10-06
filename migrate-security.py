#!/usr/bin/env python3
"""
Migrate GeoServer security from XML to PostgreSQL JDBC tables.
Parses users.xml and roles.xml and inserts into database.
"""

import xml.etree.ElementTree as ET
import psycopg2
import sys

# Database connection
DB_CONFIG = {
    'host': 'postgis',  # Docker container hostname
    'port': 5432,
    'database': 'geoserver',
    'user': 'geoserver',
    'password': 'geoserver'
}

def parse_users_xml(xml_path):
    """Parse users.xml and extract user data."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    # Handle XML namespace
    ns = {'gs': 'http://www.geoserver.org/security/users'}

    users = []
    user_props = []

    for user_elem in root.findall('.//gs:user', ns):
        name = user_elem.get('name')
        password = user_elem.get('password')
        enabled = '1' if user_elem.get('enabled') == 'true' else '0'

        users.append((name, password, enabled))

        # Extract user properties (like AuthKey UUIDs)
        for prop_elem in user_elem.findall('gs:property', ns):
            propname = prop_elem.get('name')
            propvalue = prop_elem.text
            user_props.append((name, propname, propvalue))

    return users, user_props

def parse_roles_xml(xml_path):
    """Parse roles.xml and extract role assignments."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    # Handle XML namespace
    ns = {'gs': 'http://www.geoserver.org/security/roles'}

    roles = set()
    user_roles = []

    # Parse role definitions
    for role_elem in root.findall('.//gs:role', ns):
        rolename = role_elem.get('id')
        roles.add(rolename)

    # Parse user-role assignments
    for user_elem in root.findall('.//gs:userRoles', ns):
        username = user_elem.get('username')

        for role_elem in user_elem.findall('gs:roleRef', ns):
            rolename = role_elem.get('roleID')
            roles.add(rolename)
            user_roles.append((username, rolename))

    return list(roles), user_roles

def migrate_to_database(users, user_props, roles, user_roles):
    """Insert all security data into PostgreSQL."""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    try:
        # Insert roles
        print(f"Inserting {len(roles)} roles...")
        for role in roles:
            cur.execute(
                "INSERT INTO roles (name, parent) VALUES (%s, NULL) ON CONFLICT (name) DO NOTHING",
                (role,)
            )

        # Insert users
        print(f"Inserting {len(users)} users...")
        for name, password, enabled in users:
            cur.execute(
                "INSERT INTO users (name, password, enabled) VALUES (%s, %s, %s) ON CONFLICT (name) DO NOTHING",
                (name, password, enabled)
            )

        # Insert user properties
        print(f"Inserting {len(user_props)} user properties...")
        for username, propname, propvalue in user_props:
            cur.execute(
                "INSERT INTO user_props (username, propname, propvalue) VALUES (%s, %s, %s) ON CONFLICT (username, propname) DO NOTHING",
                (username, propname, propvalue)
            )

        # Insert user-role assignments
        print(f"Inserting {len(user_roles)} user-role assignments...")
        for username, rolename in user_roles:
            cur.execute(
                "INSERT INTO user_roles (username, rolename) VALUES (%s, %s) ON CONFLICT (username, rolename) DO NOTHING",
                (username, rolename)
            )

        conn.commit()
        print("✅ Migration completed successfully!")

        # Print summary
        cur.execute("SELECT COUNT(*) FROM users")
        user_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM roles")
        role_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM user_roles")
        assignment_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM user_props")
        props_count = cur.fetchone()[0]

        print(f"\n📊 Database Summary:")
        print(f"   Users: {user_count}")
        print(f"   Roles: {role_count}")
        print(f"   User-Role Assignments: {assignment_count}")
        print(f"   User Properties: {props_count}")

    except Exception as e:
        conn.rollback()
        print(f"❌ Error during migration: {e}")
        raise
    finally:
        cur.close()
        conn.close()

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python migrate-security.py <users.xml> <roles.xml>")
        sys.exit(1)

    users_xml = sys.argv[1]
    roles_xml = sys.argv[2]

    print(f"📖 Parsing {users_xml}...")
    users, user_props = parse_users_xml(users_xml)

    print(f"📖 Parsing {roles_xml}...")
    roles, user_roles = parse_roles_xml(roles_xml)

    print(f"\n📦 Found:")
    print(f"   {len(users)} users")
    print(f"   {len(user_props)} user properties")
    print(f"   {len(roles)} unique roles")
    print(f"   {len(user_roles)} user-role assignments")

    print(f"\n🔄 Migrating to database...")
    migrate_to_database(users, user_props, roles, user_roles)
