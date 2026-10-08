#!/usr/bin/env bash
# Installs the nightly backup on the instance. Run ON THE INSTANCE.
set -euo pipefail
source /opt/campuspulse/.env

chmod +x /opt/campuspulse/ops/backup.sh
LINE="0 2 * * * AWS_REGION=${AWS_REGION} EVENTS_TABLE=${EVENTS_TABLE} BUCKET=${BUCKET} /opt/campuspulse/ops/backup.sh >> /opt/campuspulse/logs/backup.log 2>&1"
( crontab -l 2>/dev/null | grep -v campuspulse/ops/backup.sh || true ; echo "$LINE" ) | crontab -
echo "nightly backup installed at 02:00 UTC:"
crontab -l | grep backup
