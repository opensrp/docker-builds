#!/bin/bash

# create openmrs properties file
echo "creating openmrs properties file"

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
