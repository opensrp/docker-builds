#!/bin/bash

if [ -f /tmp/opensrp${APPLICATION_SUFFIX}.war ]; then
	mv /tmp/opensrp${APPLICATION_SUFFIX}.war /etc/migrations 
	echo "Shared opensrp war to runtime container"
fi

if [ -f /tmp/openmrs${APPLICATION_SUFFIX}.war ]; then
	mv /tmp/openmrs${APPLICATION_SUFFIX}.war /etc/migrations 
	echo "Shared openmrs war to runtime container"
fi

if [ -d /tmp/.OpenMRS${APPLICATION_SUFFIX} ]; then
	mv /tmp/.OpenMRS${APPLICATION_SUFFIX} /etc/migrations 
	echo "Shared openmrs data directory to runtime container"
fi

MYSQL_HOST=mysql

# create openmrs properties file
echo "Creating openmrs properties file"
if [ ! -f /etc/migrations/.OpenMRS${APPLICATION_SUFFIX}/openmrs${APPLICATION_SUFFIX}-runtime.properties ]; then
	cat > /etc/migrations/.OpenMRS${APPLICATION_SUFFIX}/openmrs${APPLICATION_SUFFIX}-runtime.properties <<- EOF
		connection.username=${MYSQL_OPENMRS_USER}
		connection.password=${MYSQL_OPENMRS_PASSWORD}
		connection.url=jdbc:mysql://${MYSQL_HOST}:3306/${MYSQL_OPENMRS_DATABASE}?autoReconnect=true&sessionVariables=storage_engine=InnoDB&useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
		module.allow_web_admin=true
		auto_update_database=false
		sync.mandatory=false
	EOF

	echo "Finished creating openmrs properties file"

fi


cd $(dirname $0)
./migrate_postgres.sh
./migrate_mysql.sh
