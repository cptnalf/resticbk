#!/bin/bash
set -eu

echo "Start pruning restic backups"

source '/etc/restic/env.sh'

MYHOST="$(hostname)"

if [ -z "$MYHOST" ]; then
  echo "Skipped prune because empty host"
  exit 0
fi

if [ "$MYHOST" != "$REPO_HOST" ]; then
  exit 0
fi

# check repo first.
restic check

# keep the last 4 snapshots
# keep only 1 snapshot for each of the last 7 days
# keep only 1 snapshot for each of the last 3 weeks
# keep only 1 snapshot for each of the last 3 months
# keep only 1 snapshot for each of the last 2 years
# only do this on saturday.
if [ $(date +%A) == "Saturday" ]; then
  restic forget \
      --keep-last 4 \
      --keep-daily 7 \
      --keep-weekly 3 \
      --keep-monthly 3 \
      --keep-yearly 2 \
      --keep-within 20d \
      --prune \
      --host $MYHOST
  echo "Finished Pruning"
else
  echo "Skipped pruning"
fi

exit 0
