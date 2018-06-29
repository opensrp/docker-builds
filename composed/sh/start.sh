#!/bin/bash

while [ ! -f /etc/migrations/.postgres_migrations_complete -o ! -f /etc/migrations/.mysql_migrations_complete ]; 
 do echo 'waiting for database migrations to complete...'; 
 sleep 5; 
done;

if ls /etc/migrations/opensrp*.war 1> /dev/null 2>&1; then
	mv /etc/migrations/opensrp*.war /opt/tomcat/instances/opensrp/webapps
	echo 'Copying opensrp war'
fi

if ls /etc/migrations/openmrs*.war 1> /dev/null 2>&1; then
	mv /etc/migrations/openmrs*.war /opt/tomcat/instances/openmrs/webapps
	echo 'Copying openmrs war'
fi

if ls /etc/migrations/openmrs*-runtime.properties 1> /dev/null 2>&1; then
	cp /etc/migrations/openmrs*-runtime.properties /opt/tomcat/.OpenMRS
	echo 'Copying openmrs runtime properties'
fi

exec /usr/bin/supervisord
