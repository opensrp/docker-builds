#!/bin/bash

while [ ! -f /etc/migrations/.postgres_migrations_complete -o ! -f /etc/migrations/.mysql_migrations_complete ]; 
 do echo 'waiting for database migrations to complete...'; 
 sleep 5; 
done;

exec /usr/bin/supervisord
