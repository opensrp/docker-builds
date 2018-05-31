#!/bin/bash
# Initialize CouchDB
echo `id`
# we need to set the permissions here because docker mounts volumes as root
exec chown -R couchdb:couchdb \
	/usr/local/var/lib/couchdb \
	/usr/local/var/log/couchdb \
	/usr/local/var/run/couchdb \
	/usr/local/etc/couchdb

exec chmod -R 0770 \
	/usr/local/var/lib/couchdb \
	/usr/local/var/log/couchdb \
	/usr/local/var/run/couchdb \
	/usr/local/etc/couchdb

exec chmod 664 /usr/local/etc/couchdb/*.ini
exec chmod 775 /usr/local/etc/couchdb/*.d

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

# Finished CouchDB Initialization

# Initialize CouchDB Lucene

chown -R couchdb:couchdb /opt/couchdb-lucene

# Finished CouchDB Lucene Initialization
id
# Initialize MySQL
set -eo pipefail
shopt -s nullglob

MYSQL_COMMAND="mysqld"
id
_check_config() {
	toRun=( "$MYSQL_COMMAND" --verbose --help --log-bin-index="$(mktemp -u)" )
	if ! errors="$("${toRun[@]}" 2>&1 >/dev/null)"; then
		cat >&2 <<-EOM

			ERROR: mysqld failed while attempting to check config
			command was: "${toRun[*]}"

			$errors
		EOM
		exit 1
	fi
}

_datadir() {
	"$MYSQL_COMMAND" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null | awk '$1 == "datadir" { print $2; exit }'
}

# allow the container to be started with `--user`
if [ "$(id -u)" = '0' ]; then
	_check_config "$MYSQL_COMMAND"
	DATADIR="$(_datadir "$MYSQL_COMMAND")"
	mkdir -p "$DATADIR"
	chown -R mysql:mysql "$DATADIR"
	exec gosu mysql "$BASH_SOURCE" "$MYSQL_COMMAND"
fi

# still need to check config, container may have started with --user
_check_config "$MYSQL_COMMAND"
# Get config
DATADIR="$(_datadir "$MYSQL_COMMAND")"

if [ ! -d "$DATADIR/mysql" ]; then
	if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
		echo >&2 'error: database is uninitialized and password option is not specified '
		echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
		exit 1
	fi

	mkdir -p "$DATADIR"
    echo "DATADIR: $DATADIR"

	echo 'Initializing database'
	mysql_install_db --datadir="$DATADIR" --rpm --keep-my-cnf
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

	if [ "$MYSQL_OPENMRS_USER" -a "$MYSQL_OPENMRS_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_OPENMRS_USER'@'%' IDENTIFIED BY '$MYSQL_OPENMRS_PASSWORD' ;" | "${mysql[@]}"

		if [ "$MYSQL_OPENMRS_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_OPENMRS_DATABASE\`.* TO '$MYSQL_OPENMRS_USER'@'%' ;" | "${mysql[@]}"
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

	# Import data
	mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_MOTECH_DATABASE" < "~/sql/tables_quartz_mysql.sql"
	mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "~/sql/openmrs.sql"
	mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "~/sql/locations.sql"
	mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_OPENMRS_DATABASE" < "~/sql/person_attribute_type.sql"

	# create openmrs properties file
	touch /root/.OpenMRS/openmrs-runtime.properties
	cat > /root/.OpenMRS/openmrs-runtime.properties <<- EOF
		connection.username=${MYSQL_OPENMRS_USER}
		connection.password=${MYSQL_OPENMRS_PASSWORD}
		connection.url=jdbc:mysql://localhost:3306/${MYSQL_OPENMRS_DATABASE}?autoReconnect=true&sessionVariables=storage_engine=InnoDB&useUnicode=true&characterEncoding=UTF-8
		module.allow_web_admin=true
		auto_update_database=false
	EOF

	if ! kill -s TERM "$pid" || ! wait "$pid"; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi

	echo
	echo 'MySQL init process done. Ready for start up.'
	echo
fi

# Finished MySQL Initialization

#Inialize Postgres

POSTGRES_COMMAND="postgres"

set -Eeo pipefail
id
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$POSTGRES_COMMAND"
fi

# allow the container to be started with `--user`
if [ "$(id -u)" = '0' ]; then
	mkdir -p "$PGDATA"
	chown -R postgres "$PGDATA"
	chmod 700 "$PGDATA"

	mkdir -p /var/run/postgresql
	chown -R postgres /var/run/postgresql
	chmod 775 /var/run/postgresql

	# Create the transaction log directory before initdb is run (below) so the directory is owned by the correct user
	if [ "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		chown -R postgres "$POSTGRES_INITDB_WALDIR"
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	exec gosu postgres "$BASH_SOURCE" "$POSTGRES_COMMAND"
fi


mkdir -p "$PGDATA"
chown -R "$(id -u)" "$PGDATA" 2>/dev/null || :
chmod 700 "$PGDATA" 2>/dev/null || :

# look specifically for PG_VERSION, as it is expected in the DB dir
if [ ! -s "$PGDATA/PG_VERSION" ]; then
	# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
	# see https://github.com/docker-library/postgres/pull/253, https://github.com/docker-library/postgres/issues/359, https://cwrap.org/nss_wrapper.html
	if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
		export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
		export NSS_WRAPPER_PASSWD="$(mktemp)"
		export NSS_WRAPPER_GROUP="$(mktemp)"
		echo "postgres:x:$(id -u):$(id -g):PostgreSQL:$PGDATA:/bin/false" > "$NSS_WRAPPER_PASSWD"
		echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
	fi

	file_env 'POSTGRES_INITDB_ARGS'
	if [ "$POSTGRES_INITDB_WALDIR" ]; then
		export POSTGRES_INITDB_ARGS="$POSTGRES_INITDB_ARGS --waldir $POSTGRES_INITDB_WALDIR"
	fi
	eval "initdb --username=postgres $POSTGRES_INITDB_ARGS"

	# unset/cleanup "nss_wrapper" bits
	if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi

	# check password first so we can output the warning before postgres
	# messes it up
	file_env 'POSTGRES_PASSWORD'
	if [ "$POSTGRES_PASSWORD" ]; then
		pass="PASSWORD '$POSTGRES_PASSWORD'"
		authMethod=md5
	else
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOWARN'
			****************************************************
			WARNING: No password has been set for the database.
			         This will allow anyone with access to the
			         Postgres port to access your database. In
			         Docker's default configuration, this is
			         effectively any other container on the same
			         system.
			         Use "-e POSTGRES_PASSWORD=password" to set
			         it in "docker run".
			****************************************************
		EOWARN

		pass=
		authMethod=trust
	fi

	{
		echo
		echo "host all all all $authMethod"
	} >> "$PGDATA/pg_hba.conf"

	# internal start of server in order to allow set-up using psql-client
	# does not listen on external TCP/IP and waits until start finishes
	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" \
		-o "-c listen_addresses=''" \
		-w start

	file_env 'POSTGRES_USER' 'postgres'
	file_env 'POSTGRES_DB' "$POSTGRES_USER"

	psql=( psql -v ON_ERROR_STOP=1 )

	if [ "$POSTGRES_DB" != 'postgres' ]; then
		"${psql[@]}" --username postgres <<-EOSQL
			CREATE DATABASE "$POSTGRES_DB" ;
		EOSQL
		echo
	fi

	if [ "$POSTGRES_USER" = 'postgres' ]; then
		op='ALTER'
	else
		op='CREATE'
	fi
	"${psql[@]}" --username postgres <<-EOSQL
		$op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
	EOSQL
	echo

	psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

	echo
	for f in /docker-entrypoint-initdb.d/*; do
		case "$f" in
			*.sh)     echo "$0: running $f"; . "$f" ;;
			*.sql)    echo "$0: running $f"; "${psql[@]}" -f "$f"; echo ;;
			*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
			*)        echo "$0: ignoring $f" ;;
		esac
		echo
	done

	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" -m fast -w stop

	echo
	echo 'PostgreSQL init process complete; ready for start up.'
	echo
fi
id
#Finished Postgres Initialization

exec /usr/bin/supervisord
