#!/bin/bash

# Import data

MYSQL_HOST=mysql
MYSQL_PORT=3306

echo "wait for mysql to be ready"

while ! nc -q 1 ${MYSQL_HOST} ${MYSQL_PORT} </dev/null;
do
  echo "Waiting for database"
  sleep 10;
done

echo "Importing mysql data from backups"

mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h "$MYSQL_HOST" -e "CREATE DATABASE $MYSQL_MOTECH_DATABASE /*\!40100 DEFAULT CHARACTER SET utf8 */;"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h "$MYSQL_HOST" "$MYSQL_MOTECH_DATABASE" < "/opt/sql/tables_quartz_mysql.sql"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h "$MYSQL_HOST" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/openmrs.sql"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h "$MYSQL_HOST" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/locations.sql"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h "$MYSQL_HOST" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/person_attribute_type.sql"

echo "Finished importing mysql data"

# create openmrs properties file
echo "Creating openmrs properties file"

touch /root/.OpenMRS/openmrs-runtime.properties
cat > /root/.OpenMRS/openmrs-runtime.properties <<- EOF
	connection.username=${MYSQL_OPENMRS_USER}
	connection.password=${MYSQL_OPENMRS_PASSWORD}
	connection.url=jdbc:mysql://${MYSQL_HOST}:3306/${MYSQL_OPENMRS_DATABASE}?autoReconnect=true&sessionVariables=storage_engine=InnoDB&useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
	module.allow_web_admin=true
	auto_update_database=false
	sync.mandatory=false
EOF

echo "Finished creating openmrs properties file"


exec /usr/bin/supervisord
