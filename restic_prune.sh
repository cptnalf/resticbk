#!/bin/bash
set -eu

echo "Start pruning restic backups"

source '/etc/restic/env.sh'
HOSTS_LIST_SRC=/etc/restic/backup_hosts

MYHOST="$(hostname)"

if [ -z "$MYHOST" ]; then
  echo "Skipped prune because empty host"
  exit 0
fi

if [ "$MYHOST" != "$REPO_HOST" ]; then
  exit 0
fi

if [ ! -f $HOSTS_LIST_SRC ]; then
  echo "Hosts list doesn't exist."
  exit 0
fi

# check repo first.
restic check

# parses the hosts list.
HOSTS_LIST=`sed -e '/^$/d;/^[[:blank:]]*#/d;s/#.*//' $HOSTS_LIST_SRC | sed -e :a -e '$!N; s/\n/ /; ta'`
hosts_arr=($HOSTS_LIST)

# keep the last 4 snapshots
# keep only 1 snapshot for each of the last 7 days
# keep only 1 snapshot for each of the last 3 weeks
# keep only 1 snapshot for each of the last 6 months
# keep only 1 snapshot for each of the last 2 years
# only do this on saturday.
if [ $(date +%A) == "Saturday" ]; then
  for h in ${hosts_arr[@]};
  do
    restic forget \
        --keep-last 4 \
        --keep-daily 7 \
        --keep-weekly 3 \
        --keep-monthly 6 \
        --keep-yearly 2 \
        --keep-within 20d \
        --prune \
        --host $h
    echo "Pruned $h"
  done
  echo "Finished Pruning"
else
  echo "Skipped pruning"
fi

exit 0
