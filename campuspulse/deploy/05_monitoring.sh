#!/usr/bin/env bash
# Observability: log group, an email alert channel, four alarms and one
# dashboard. Check usage and account-specific pricing rather than assuming
# monitoring is free; metric dimensions and log volume affect consumption.
set -euo pipefail
source "$(dirname "$0")/00_config.sh"
need INSTANCE_ID

if [ "$ALERT_EMAIL" = "CHANGE_ME@example.com" ]; then
  echo "set ALERT_EMAIL first:  export ALERT_EMAIL=you@example.com" >&2
  exit 1
fi

echo "== log group (7 day retention limits stored logs)"
aws logs create-log-group --log-group-name "$LOG_GROUP" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 7

echo "== alert channel"
TOPIC_ARN=$(aws sns create-topic --name "${PROJECT}-alerts" --query TopicArn --output text)
save TOPIC_ARN "$TOPIC_ARN"
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$ALERT_EMAIL" >/dev/null
echo "   confirm the subscription in your inbox, otherwise no alert is delivered"

echo "== metric filter: count ERROR lines written by the API"
aws logs put-metric-filter \
  --log-group-name "$LOG_GROUP" \
  --filter-name "${PROJECT}-error-lines" \
  --filter-pattern '{ $.level = "error" }' \
  --metric-transformations \
     "metricName=ApiErrors,metricNamespace=${METRIC_NS},metricValue=1,defaultValue=0"

echo "== alarms"
aws cloudwatch put-metric-alarm \
  --alarm-name "${PROJECT}-critical-events" \
  --alarm-description "A critical campus event was ingested" \
  --namespace "$METRIC_NS" --metric-name AbnormalEvents \
  --dimensions Name=Severity,Value=critical \
  --statistic Sum --period 300 --evaluation-periods 1 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN"

aws cloudwatch put-metric-alarm \
  --alarm-name "${PROJECT}-api-errors" \
  --alarm-description "The API logged 5 or more errors in 5 minutes" \
  --namespace "$METRIC_NS" --metric-name ApiErrors \
  --statistic Sum --period 300 --evaluation-periods 1 --threshold 5 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN"

aws cloudwatch put-metric-alarm \
  --alarm-name "${PROJECT}-cpu-high" \
  --alarm-description "Instance CPU above 80 percent for 10 minutes" \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average --period 300 --evaluation-periods 2 --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$TOPIC_ARN"

aws cloudwatch put-metric-alarm \
  --alarm-name "${PROJECT}-instance-unhealthy" \
  --alarm-description "EC2 status check failed - instance or host is broken" \
  --namespace AWS/EC2 --metric-name StatusCheckFailed \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Maximum --period 60 --evaluation-periods 2 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "$TOPIC_ARN"

echo "== dashboard"
cat > /tmp/${PROJECT}-dash.json <<JSON
{"widgets":[
 {"type":"metric","x":0,"y":0,"width":12,"height":6,
  "properties":{"title":"Abnormal events by severity","region":"${AWS_REGION}","stat":"Sum","period":300,
   "metrics":[["${METRIC_NS}","AbnormalEvents","Severity","critical"],
              ["...","warning"]]}},
 {"type":"metric","x":12,"y":0,"width":12,"height":6,
  "properties":{"title":"Instance CPU","region":"${AWS_REGION}","stat":"Average","period":300,
   "metrics":[["AWS/EC2","CPUUtilization","InstanceId","${INSTANCE_ID}"]]}},
 {"type":"metric","x":0,"y":6,"width":12,"height":6,
  "properties":{"title":"DynamoDB consumed capacity","region":"${AWS_REGION}","stat":"Sum","period":300,
   "metrics":[["AWS/DynamoDB","ConsumedWriteCapacityUnits","TableName","${EVENTS_TABLE}"],
              ["AWS/DynamoDB","ConsumedReadCapacityUnits","TableName","${EVENTS_TABLE}"]]}},
 {"type":"log","x":12,"y":6,"width":12,"height":6,
  "properties":{"title":"Recent API log","region":"${AWS_REGION}",
   "query":"SOURCE '${LOG_GROUP}' | fields @timestamp, msg, severity, building, room\\n| sort @timestamp desc\\n| limit 20"}}
]}
JSON
aws cloudwatch put-dashboard --dashboard-name "${PROJECT}-ops" \
  --dashboard-body "file:///tmp/${PROJECT}-dash.json" >/dev/null

echo
echo "observability ready. Dashboard: CloudWatch > Dashboards > ${PROJECT}-ops"
