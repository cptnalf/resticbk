#!/bin/bash
set -eu

source '/etc/restic/env.sh'

echo "Starting restic backup"

if ! restic snapshots 2>&1 > /dev/null; then
  restic init
fi

# check if repo is ok.

restic check

BACKUP_LIST=`sed -e '/^$/d;/^[[:blank:]]*#/d;s/#.*//' $BACKUP_LIST_SRC | sed -e :a -e '$!N; s/\n/ /; ta'`

if [ -z "${BACKUP_LIST}" ]; then
  echo "Nothing to do!"
  exit 1
fi

restic backup \
  --one-file-system \
  --exclude-caches \
  $BACKUP_LIST

echo "Finished restic backup"

exit 0
