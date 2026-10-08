# Operations and recovery

## Account maintenance

Use `docker compose exec api python manage_user.py USER --role ROLE` from `/opt/campuspulse`, with sudo if required. Existing accounts are `ops.admin`, `front.desk` and `sensor.fleet`. Passwords are prompted privately and a conditional PutItem preserves other attributes. Do not paste credentials, JWTs or password hashes into issues or commits. A password reset does not revoke previously issued JWTs; they remain valid until expiry.

## Monitoring

Dashboard: `campuspulse-ops`. Application log group: `/campuspulse/app`, seven-day retention. Alarms: critical events, API errors, CPU high and instance unhealthy. SNS topic: `campuspulse-alerts`. Alarm email delivery requires a confirmed subscription.

Useful Logs Insights query:

```text
fields @timestamp, msg, severity, building, room
| filter severity = "critical"
| sort @timestamp desc
| limit 20
```

The service logs expected authentication/role failures as warnings. The API-error alarm depends on emitted error-level records; it does not automatically count every HTTP 5xx. The prototype does not implement login rate limiting or WAF protection.

The budget is a notification mechanism, not an automatic spending cap. October 8 screenshots showed $15.28 actual account-wide spend against $20, a $65.85 forecast, and the forecast threshold exceeded. September was $31. These are dated observations, not live billing values or CampusPulse-only totals. The Lab 3 NAT gateway is intentionally retained at the user's direction.

## Backup and restore

`ops/install_cron.sh` installs an events-table backup at 02:00 host time using resource names in `/opt/campuspulse/.env`. On the host, `sudo crontab -l` checks the installed root schedule; inspect the bucket and `logs/backup.log` to confirm successful executions. For a manual backup, supply BUCKET and the region/table environment variables to `ops/backup.sh`.

The dump is gzip JSON containing DynamoDB's typed `Items`. It is a logical scan, not a transactionally consistent snapshot of concurrent writes. It backs up the events table, not users or IAM/network configuration. Verify backup freshness before reporting an achieved RPO.

For a restore drill, use an operator identity rather than the application's runtime role. Create a scratch table with partition key `building` (String) and sort key `event_ts` (String), then:

```bash
./campuspulse/ops/restore.sh s3://YOUR_BUCKET/backups/campuspulse-events/YOUR_DUMP.json.gz campuspulse-events-restored
```

The operator's Python environment needs boto3 and its shell needs AWS CLI. The operator needs S3 read plus DynamoDB BatchWriteItem on the scratch table. The runtime role intentionally lacks recovery access to arbitrary tables. Never use the live table as a test target. Verify item counts and sample contents; rebuild the severity GSI and other settings if preparing an actual replacement table. Measure creation, restore and cutover separately. Remove the scratch table after the drill when approved.

## Deployment troubleshooting

- SSM not connected: confirm AmazonSSMManagedInstanceCore is attached and the agent is running. The live host connected after a reboot following attachment.
- API log PermissionError: `/opt/campuspulse/logs` must be writable by UID 10001.
- HTTPS inaccessible: check DNS, inbound 443, Docker's port mapping, certificate files and `docker exec campuspulse-web nginx -t`.
- Renewals: run `sudo certbot renew --dry-run --run-deploy-hooks` and inspect `certbot.timer`. Nginx success messages use stderr and can appear red in Certbot output; check the final success/failure result.
- Multiline browser-terminal paste: use short individual commands or scripts already on disk. In-place config writes preserve Docker's individual file bind mount; replacing a file's inode requires recreating the web container.
- Zero dashboard events: the configured event TTL is 30 days. Check current ingestion and API responses before interpreting an empty display as a failure.

## Cleanup after demonstration

Cleanup has **not** been performed. Review exact resource identities and keep anything required for the presentation. Do not touch Lab 3's NAT gateway or other coursework resources. There is no automatic destructive teardown command in this repository.

When cleanup is approved, use the stored project state and AWS console to review: EC2 instance and attached volumes; project DynamoDB tables/PITR and scratch tables; S3 object versions and delete markers; project log group/dashboard/alarms and SNS subscriptions/topic; signing parameter; project IAM policy/role/profile; subnet route associations, subnets, security group, internet gateway and VPC; unused project key pair; and project DNS record. Keep backups until explicitly no longer required. Deleting a versioned bucket requires clearing all versions and delete markers. Review the account-wide budget before deleting it, since other labs still consume resources. Confirm resource deletion and later billing updates rather than assuming the account total becomes zero.
