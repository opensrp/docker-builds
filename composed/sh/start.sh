#!/bin/bash

MYSQL_HOST=mysql

# create openmrs properties file
echo "Creating openmrs properties file"

if [ ! -f /opt/tomcat/.OpenMRS/openmrs-runtime.properties ]; then
	cat > /opt/tomcat/.OpenMRS/openmrs-runtime.properties <<- EOF
		connection.username=${MYSQL_OPENMRS_USER}
		connection.password=${MYSQL_OPENMRS_PASSWORD}
		connection.url=jdbc:mysql://${MYSQL_HOST}:3306/${MYSQL_OPENMRS_DATABASE}?autoReconnect=true&sessionVariables=storage_engine=InnoDB&useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
		module.allow_web_admin=true
		auto_update_database=false
		sync.mandatory=false
	EOF

	echo "Finished creating openmrs properties file"

fi

exec /usr/bin/supervisord
