#!/usr/bin/env bash
# Nightly logical backup: dump the events table to compressed JSON in S3.
# Runs ON THE INSTANCE from cron. DynamoDB point-in-time recovery already
# covers the last 35 days; this second copy protects against the table
# being deleted. This logical copy has a separate retention policy.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-3}"
TABLE="${EVENTS_TABLE:-campuspulse-events}"
BUCKET="${BUCKET:?set BUCKET}"
STAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
OUT="/tmp/${TABLE}-${STAMP}.json"

aws dynamodb scan --table-name "$TABLE" --region "$REGION" --output json > "$OUT"
gzip -f "$OUT"
aws s3 cp "${OUT}.gz" "s3://${BUCKET}/backups/${TABLE}/${STAMP}.json.gz" \
  --region "$REGION" --sse AES256
rm -f "${OUT}.gz"

echo "{\"level\":\"info\",\"msg\":\"backup_ok\",\"table\":\"${TABLE}\",\"stamp\":\"${STAMP}\"}" \
  >> /opt/campuspulse/logs/app.log 2>/dev/null || true
