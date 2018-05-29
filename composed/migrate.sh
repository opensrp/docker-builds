#!/bin/bash
: ${DB_ENV_POSTGRES_USER:=postgres}
: ${DB_ENV_POSTGRES_SCHEMA:=postgres}

cat <<CONF > /migrate/environments/development.properties
time_zone=GMT+0:00
driver=org.postgresql.Driver
url=jdbc:postgresql://$DB_PORT_5432_TCP_ADDR:$DB_PORT_5432_TCP_PORT/$DB_ENV_POSTGRES_SCHEMA
username=$DB_ENV_POSTGRES_USER
password=$DB_ENV_POSTGRES_PASSWORD
script_char_set=UTF-8
send_full_script=true
delimiter=;
full_line_delimiter=false
auto_commit=true
changelog=changelog
CONF

echo $OPENSRP_TABLESPACE_ROOT

mkdir -p $OPENSRP_TABLESPACE_ROOT/core
mkdir -p $OPENSRP_TABLESPACE_ROOT/error
mkdir -p $OPENSRP_TABLESPACE_ROOT/schedule
mkdir -p $OPENSRP_TABLESPACE_ROOT/feed
mkdir -p $OPENSRP_TABLESPACE_ROOT/form

groupadd -r postgres --gid=999 && useradd -r -g postgres --uid=999 postgres

chown -R postgres $OPENSRP_TABLESPACE_ROOT

while ! nc -q 1 $DB_PORT_5432_TCP_ADDR $DB_PORT_5432_TCP_PORT </dev/null;
do
  echo "Waiting for database"
  sleep 10;
done

/opt/mybatis-migrations-3.3.4/bin/migrate up