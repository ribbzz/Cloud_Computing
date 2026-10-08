#!/usr/bin/env bash
# The restore half of the DR plan. Time this while you run it once - the
# measured number is data-copy time, not full infrastructure recovery time.
#
#   ./restore.sh s3://campuspulse-backups-123456789012/backups/campuspulse-events/2026-05-10T02-00-00Z.json.gz
set -euo pipefail

SRC="${1:?usage: restore.sh s3://bucket/key.json.gz [target-table]}"
TARGET="${2:-${EVENTS_TABLE:-campuspulse-events}}"
REGION="${AWS_REGION:-eu-west-3}"

echo "restoring ${SRC} into ${TARGET}"
aws s3 cp "$SRC" /tmp/restore.json.gz --region "$REGION"
gunzip -f /tmp/restore.json.gz

python3 - "$TARGET" "$REGION" <<'PY'
import json, sys, boto3
target, region = sys.argv[1], sys.argv[2]
data = json.load(open("/tmp/restore.json"))
client = boto3.client("dynamodb", region_name=region)
items = data["Items"]
for i in range(0, len(items), 25):                     # BatchWriteItem caps at 25
    batch = [{"PutRequest": {"Item": it}} for it in items[i:i + 25]]
    resp = client.batch_write_item(RequestItems={target: batch})
    while resp.get("UnprocessedItems"):                # retry throttled writes
        resp = client.batch_write_item(RequestItems=resp["UnprocessedItems"])
    print(f"  restored {min(i + 25, len(items))}/{len(items)}", end="\r")
print(f"\nrestored {len(items)} items into {target}")
PY
rm -f /tmp/restore.json
