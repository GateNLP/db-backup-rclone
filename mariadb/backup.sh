#!/bin/sh

set -eo pipefail

function do_dump_all() {
  mariadb-dump "$@" --all-databases --single-transaction
}

function do_dump_one() {
  local DBNAME="$1"
  shift
  mariadb-dump "$@" --single-transaction --databases "$DBNAME"
}

. /common.sh

# Sanity check MariaDB configuration
if [ -z "${MYSQL_PWD}" ]; then
  if [ -n "${MYSQL_PWD_FILE}" ]; then
    IFS= read MYSQL_PWD < "${MYSQL_PWD_FILE}"
    export MYSQL_PWD
  fi
fi

do_backup "$@"
