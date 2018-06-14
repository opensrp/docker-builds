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

# create openmrs properties file
echo "Creating openmrs properties file"

touch /opt/tomcat/.OpenMRS/openmrs-runtime.properties
cat > /opt/tomcat/.OpenMRS/openmrs-runtime.properties <<- EOF
	connection.username=${MYSQL_OPENMRS_USER}
	connection.password=${MYSQL_OPENMRS_PASSWORD}
	connection.url=jdbc:mysql://${MYSQL_HOST}:3306/${MYSQL_OPENMRS_DATABASE}?autoReconnect=true&sessionVariables=storage_engine=InnoDB&useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
	module.allow_web_admin=true
	auto_update_database=false
	sync.mandatory=false
EOF

echo "Finished creating openmrs properties file"


exec /usr/bin/supervisord
