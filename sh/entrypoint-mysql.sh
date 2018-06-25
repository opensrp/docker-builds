#!/bin/bash

# Initialize MySQL
echo "Initializing MySQL"

set -eo pipefail
shopt -s nullglob

MYSQL_COMMAND="mysqld"

# allow the container to be started with `--user`
if [ "$(id -u)" = '0' ]; then
	mkdir -p "$MSDATA"
	chown -R mysql:mysql "$MSDATA"
	exec gosu mysql "$BASH_SOURCE" "$MYSQL_COMMAND"
fi

# still need to check config, container may have started with --user
if [ ! -d "$MSDATA/mysql" ]; then
	if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
		echo >&2 'error: database is uninitialized and password option is not specified '
		echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
		exit 1
	fi

	mkdir -p "$MSDATA"
    echo "DATADIR: $MSDATA"

	echo 'Initializing database'
	mysql_install_db --datadir="$MSDATA" --rpm
	echo 'Database initialized'

	"$MYSQL_COMMAND" --skip-networking &
	pid="$!"

	mysql=( mysql --protocol=socket -uroot )

	for i in {30..0}; do
		if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
			break
		fi
		echo 'MySQL init process in progress...'
		sleep 1
	done
	if [ "$i" = 0 ]; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi

	if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
		# sed is for https://bugs.mysql.com/bug.php?id=20545
		mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
	fi

	if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
		MYSQL_ROOT_PASSWORD="$(pwgen -1 32)"
		echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
	fi
	"${mysql[@]}" <<-EOSQL
		-- What's done in this file shouldn't be replicated
		--  or products like mysql-fabric won't work
		SET @@SESSION.SQL_LOG_BIN=0;

		DELETE FROM mysql.user ;
		CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
		GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
		DROP DATABASE IF EXISTS test ;
		FLUSH PRIVILEGES ;
	EOSQL

	if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
		mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
	fi


	if [ "$MYSQL_MOTECH_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_MOTECH_DATABASE\` ;" | "${mysql[@]}"
	fi

	if [ "$MYSQL_OPENMRS_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_OPENMRS_DATABASE\` ;" | "${mysql[@]}"
		mysql+=( "$MYSQL_OPENMRS_DATABASE" )
	fi

	if [ "$MYSQL_OPENSRP_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_OPENSRP_DATABASE\` ;" | "${mysql[@]}"
	fi

	if [ "$MYSQL_REPORTING_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_REPORTING_DATABASE\` ;" | "${mysql[@]}"
	fi

	if [ "$MYSQL_ANM_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_ANM_DATABASE\` ;" | "${mysql[@]}"
	fi

	if [ "$MYSQL_OPENMRS_USER" -a "$MYSQL_OPENMRS_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_OPENMRS_USER'@'%' IDENTIFIED BY '$MYSQL_OPENMRS_PASSWORD' ;" | "${mysql[@]}"

		if [ "$MYSQL_OPENMRS_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_OPENMRS_DATABASE\`.* TO '$MYSQL_OPENMRS_USER'@'%' ;" | "${mysql[@]}"
		fi

		echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
	fi

	if [ "$MYSQL_OPENSRP_USER" -a "$MYSQL_OPENSRP_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_OPENSRP_USER'@'%' IDENTIFIED BY '$MYSQL_OPENSRP_PASSWORD' ;" | "${mysql[@]}"

		if [ "$MYSQL_OPENSRP_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_OPENSRP_DATABASE\`.* TO '$MYSQL_OPENSRP_USER'@'%' ;" | "${mysql[@]}"
		fi

		if [ "$MYSQL_MOTECH_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_MOTECH_DATABASE\`.* TO '$MYSQL_OPENSRP_USER'@'%' ;" | "${mysql[@]}"
		fi

		if [ "$MYSQL_REPORTING_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_REPORTING_DATABASE\`.* TO '$MYSQL_OPENSRP_USER'@'%' ;" | "${mysql[@]}"
		fi
		
		if [ "$MYSQL_ANM_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_ANM_DATABASE\`.* TO '$MYSQL_OPENSRP_USER'@'%' ;" | "${mysql[@]}"
		fi

		echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
	fi

	echo
	for f in /docker-entrypoint-initdb.d/*; do
		case "$f" in
			*.sh)     echo "$0: running $f"; . "$f" ;;
			*.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
			*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
			*)        echo "$0: ignoring $f" ;;
		esac
		echo
	done

	if [ ! -z "$MYSQL_ONETIME_PASSWORD" ]; then
		"${mysql[@]}" <<-EOSQL
			ALTER USER 'root'@'%' PASSWORD EXPIRE;
		EOSQL
	fi

	if [ ! -f /etc/migrations/.mysql_migrations_complete ]; then

		echo "Importing mysql data from backups"

		# Import data
		mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_MOTECH_DATABASE" < "/opt/sql/tables_quartz_mysql.sql"

		if [[ -n $DEMO_DATA_TAG ]];then
			wget --quiet --no-cookies https://s3-eu-west-1.amazonaws.com/opensrp-stage/demo/${DEMO_DATA_TAG}/sql/openmrs.sql.gz -O /tmp/openmrs.sql.gz
			if [[ -f /tmp/openmrs.sql.gz ]]; then
				gunzip /tmp/openmrs.sql.gz
				mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h "$MYSQL_HOST" "$MYSQL_OPENMRS_DATABASE" < "/tmp/openmrs.sql"
			fi
		fi
		#import demo data if demo data tag was not passed it was possible to extract the demo data 		
		if [[ ! -f /tmp/openmrs.sql ]]; then
			mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/openmrs.sql"
			mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/locations.sql"
			mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/person_attribute_type.sql"
			mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "/opt/sql/openmrs_user_property_trigger.sql"
		fi

		echo "Do not remove!!!. This file is generated by Docker. Removing this file will reset mysql database" > /etc/migrations/.mysql_migrations_complete  
		

		echo "Finished importing mysql data"

	fi

	if ! kill -s TERM "$pid" || ! wait "$pid"; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi

	echo
	echo 'MySQL init process done. Ready for start up.'
	echo
fi

# Finished MySQL Initialization