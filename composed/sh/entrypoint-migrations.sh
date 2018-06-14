#!/bin/bash
cd $(dirname $0)
./migrate_postgres.sh
./migrate_mysql.sh