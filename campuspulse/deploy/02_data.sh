#!/usr/bin/env bash
# Persistent storage: two DynamoDB tables and one S3 bucket for backups.
# Provisioned capacity bounds throughput; account-specific billing and credits
# must be checked separately. PITR, storage and usage can incur charges.
set -euo pipefail
source "$(dirname "$0")/00_config.sh"

echo "== events table (5 RCU / 5 WCU + a 5/5 global secondary index)"
aws dynamodb create-table \
  --table-name "$EVENTS_TABLE" \
  --attribute-definitions \
      AttributeName=building,AttributeType=S \
      AttributeName=event_ts,AttributeType=S \
      AttributeName=severity,AttributeType=S \
  --key-schema \
      AttributeName=building,KeyType=HASH \
      AttributeName=event_ts,KeyType=RANGE \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --global-secondary-indexes \
      '[{"IndexName":"severity-index",
         "KeySchema":[{"AttributeName":"severity","KeyType":"HASH"},
                      {"AttributeName":"event_ts","KeyType":"RANGE"}],
         "Projection":{"ProjectionType":"ALL"},
         "ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":5}}]' \
  --tags Key=Project,Value="$PROJECT" >/dev/null

echo "== users table (1 RCU / 1 WCU, it is read once per login)"
aws dynamodb create-table \
  --table-name "$USERS_TABLE" \
  --attribute-definitions AttributeName=username,AttributeType=S \
  --key-schema AttributeName=username,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
  --tags Key=Project,Value="$PROJECT" >/dev/null

echo "   waiting for both tables to become ACTIVE..."
aws dynamodb wait table-exists --table-name "$EVENTS_TABLE"
aws dynamodb wait table-exists --table-name "$USERS_TABLE"

echo "== 30 day time-to-live on events (limits retained data)"
aws dynamodb update-time-to-live --table-name "$EVENTS_TABLE" \
  --time-to-live-specification "Enabled=true,AttributeName=ttl" >/dev/null

echo "== point-in-time recovery (continuous backup, 35 day window)"
aws dynamodb update-continuous-backups --table-name "$EVENTS_TABLE" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true >/dev/null

BUCKET="${PROJECT}-backups-${ACCOUNT_ID}"
save BUCKET "$BUCKET"
echo "== S3 bucket ${BUCKET}"
aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
  --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration '{"Rules":[{
      "ID":"expire-old-backups","Status":"Enabled","Filter":{"Prefix":"backups/"},
      "Expiration":{"Days":30},
      "NoncurrentVersionExpiration":{"NoncurrentDays":7}}]}'

echo
echo "storage ready."
