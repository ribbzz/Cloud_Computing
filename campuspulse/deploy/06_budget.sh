#!/usr/bin/env bash
# The cost guard the brief requires evidence of.
# Two notifications: one when actual spend passes 80 percent of the budget,
# one when AWS forecasts the month will exceed it.
set -euo pipefail
source "$(dirname "$0")/00_config.sh"

if [ "$ALERT_EMAIL" = "CHANGE_ME@example.com" ]; then
  echo "set ALERT_EMAIL first:  export ALERT_EMAIL=you@example.com" >&2
  exit 1
fi

cat > /tmp/${PROJECT}-budget.json <<JSON
{
  "BudgetName": "${PROJECT}-monthly",
  "BudgetLimit": {"Amount": "${MONTHLY_BUDGET_USD}", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostTypes": {"IncludeCredit": false, "IncludeRefund": false}
}
JSON

cat > /tmp/${PROJECT}-notifications.json <<JSON
[
 {"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN",
   "Threshold":80,"ThresholdType":"PERCENTAGE"},
  "Subscribers":[{"SubscriptionType":"EMAIL","Address":"${ALERT_EMAIL}"}]},
 {"Notification":{"NotificationType":"FORECASTED","ComparisonOperator":"GREATER_THAN",
   "Threshold":100,"ThresholdType":"PERCENTAGE"},
  "Subscribers":[{"SubscriptionType":"EMAIL","Address":"${ALERT_EMAIL}"}]}
]
JSON

aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget "file:///tmp/${PROJECT}-budget.json" \
  --notifications-with-subscribers "file:///tmp/${PROJECT}-notifications.json"

echo "budget of \$${MONTHLY_BUDGET_USD}/month created with alerts to ${ALERT_EMAIL}"
echo "screenshot this in the console: Billing > Budgets  (report evidence)"
