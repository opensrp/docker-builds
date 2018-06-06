#!/bin/bash

# Create migration properties file
echo "Creating migration properties file"

cat <<CONF > /migrate/environments/development.properties
time_zone=GMT+0:00
driver=org.postgresql.Driver
url=jdbc:postgresql://localhost:5432/$POSTGRES_OPENSRP_DATABASE
username=$POSTGRES_OPENSRP_USER
password=$POSTGRES_OPENSRP_PASSWORD
script_char_set=UTF-8
send_full_script=true
delimiter=;
full_line_delimiter=false
auto_commit=true
changelog=changelog
CONF

echo "Migration properties file created"


# Create opensrp table space root directory
echo "Creating opensrp tablespace root directory"

echo $POSTGRES_OPENSRP_TABLESPACE_DIR

mkdir -p $POSTGRES_OPENSRP_TABLESPACE_DIR/core
mkdir -p $POSTGRES_OPENSRP_TABLESPACE_DIR/error
mkdir -p $POSTGRES_OPENSRP_TABLESPACE_DIR/schedule
mkdir -p $POSTGRES_OPENSRP_TABLESPACE_DIR/feed
mkdir -p $POSTGRES_OPENSRP_TABLESPACE_DIR/form

chown -R postgres $POSTGRES_OPENSRP_TABLESPACE_DIR

echo "OpenSRP tablespace root directory created"

# Create openmrs properties file
echo "Creating openmrs properties file"

touch /root/.OpenMRS/openmrs-runtime.properties
cat > /root/.OpenMRS/openmrs-runtime.properties <<- EOF
	connection.username=${MYSQL_OPENMRS_USER}
	connection.password=${MYSQL_OPENMRS_PASSWORD}
	connection.url=jdbc:mysql://localhost:3306/${MYSQL_OPENMRS_DATABASE}?autoReconnect=true&sessionVariables=storage_engine=InnoDB&useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
	module.allow_web_admin=true
	auto_update_database=false
	sync.mandatory=false
EOF

echo "openmrs properties file created"


# Initialize CouchDB
echo "Initializing CouchDB"
# we need to set the permissions here because docker mounts volumes as root
chown -R couchdb:couchdb \
	/usr/local/var/lib/couchdb \
	/usr/local/var/log/couchdb \
	/usr/local/var/run/couchdb \
	/usr/local/etc/couchdb

chmod -R 0770 \
	/usr/local/var/lib/couchdb \
	/usr/local/var/log/couchdb \
	/usr/local/var/run/couchdb \
	/usr/local/etc/couchdb

chmod 664 /usr/local/etc/couchdb/*.ini
chmod 775 /usr/local/etc/couchdb/*.d

if [ "$COUCHDB_USER" ] && [ "$COUCHDB_PASSWORD" ]; then
	# Create admin
	printf "[admins]\n$COUCHDB_USER = $COUCHDB_PASSWORD\n" > /usr/local/etc/couchdb/local.d/docker.ini
	chown couchdb:couchdb /usr/local/etc/couchdb/local.d/docker.ini
fi

# if we don't find an [admins] section followed by a non-comment, display a warning
if ! grep -Pzoqr '\[admins\]\n[^;]\w+' /usr/local/etc/couchdb; then
	# The - option suppresses leading tabs but *not* spaces. :)
	cat >&2 <<-'EOWARN'
		****************************************************
		WARNING: CouchDB is running in Admin Party mode.
		         This will allow anyone with access to the
		         CouchDB port to access your database. In
		         Docker's default configuration, this is
		         effectively any other container on the same
		         system.
		         Use "-e COUCHDB_USER=admin -e COUCHDB_PASSWORD=password"
		         to set it in "docker run".
		****************************************************
	EOWARN
fi

echo "Finished CouchDB Initialization"
# Finished CouchDB Initialization

# Initialize CouchDB Lucene
echo "Initialize CouchDB Lucene"

chown -R couchdb:couchdb /opt/couchdb-lucene

echo "Finished CouchDB Lucene Initialization"
# Finished CouchDB Lucene Initialization

cd $(dirname $0)
./entrypoint-mysql.sh
./entrypoint-postgres.sh

exec /usr/bin/supervisord
