#!/bin/sh

set -eo pipefail

function do_dump_all() {
  pg_dumpall "$@"
}

function do_dump_one() {
  local DBNAME="$1"
  shift
  pg_dump "$@" -d "$DBNAME"
}

. /common.sh

# Sanity check Postgresql configuration
if [ -z "${PGPASSWORD}" ]; then
  if [ -n "${PGPASSWORD_FILE}" ]; then
    IFS= read PGPASSWORD < "${PGPASSWORD_FILE}"
    export PGPASSWORD
  fi
fi

do_backup "$@"
