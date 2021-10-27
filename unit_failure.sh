#!/bin/bash

set -eu

UNIT="$1"
EMAIL="$2"

# get logs from last invocation.
ID=$(systemctl show -p InvocationID --value "$UNIT")
LOGS="$(journalctl --no-hostname -o short-iso INVOCATION_ID=${ID} + _SYSTEMD_INVOCATION_ID=${ID})"

# send email notifcation.
# needs working mailer ;_;
echo "$LOGS" | mail -s "Service $UNIT on $(hostname -f) failed!" "$EMAIL"

exit 0
