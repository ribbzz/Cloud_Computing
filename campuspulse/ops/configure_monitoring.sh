#!/usr/bin/env bash
# Run with sudo on the instance after deploy/05_monitoring.sh creates the log group.
set -euo pipefail
LOG_GROUP="${LOG_GROUP:-/campuspulse/app}"
METRIC_NS="${METRIC_NS:-CampusPulse}"
sed -e "s|__LOG_GROUP__|${LOG_GROUP}|g" -e "s|__METRIC_NS__|${METRIC_NS}|g" \
  /opt/campuspulse/cloudwatch-agent.json > /tmp/campuspulse-cw-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/tmp/campuspulse-cw-agent.json -s
