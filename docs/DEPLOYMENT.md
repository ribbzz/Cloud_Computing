# Deployment guide

The source under `campuspulse/` targets Ubuntu 24.04, Python 3.12, AWS `eu-west-3`, and the default project name `campuspulse`. The existing demo is at https://cloud.learningtheory.xyz. These steps reproduce the prototype; they have not been rerun against a second fresh AWS account as part of repository preparation.

## 1. Operator prerequisites

On your computer: Git, Bash, AWS CLI v2, curl, OpenSSL, rsync, SSH and Python. Authenticate AWS CLI with an operator identity allowed to create the documented resources. Do not put AWS keys in the repository or on the instance. Set a real alert email and confirm AWS's notification subscription/verification messages when requested.

```bash
git clone https://github.com/ribbzz/Cloud_Computing.git
cd Cloud_Computing/campuspulse
export AWS_REGION=eu-west-3
export ALERT_EMAIL=you@example.com
export MONTHLY_BUDGET_USD=20
aws sts get-caller-identity
```

Creation scripts are sequential, stateful provisioning utilities, not idempotent infrastructure-as-code. They save resource IDs in ignored `deploy/state.env`. Keep that file private and backed up. Do not execute them on the existing CampusPulse account simply to update application code. After a partial failure, inspect the resources already created before retrying. The S3 creation script assumes a region other than us-east-1.

## 2. Fresh AWS infrastructure

```bash
./deploy/06_budget.sh
./deploy/01_network.sh
./deploy/02_data.sh
./deploy/03_iam_secrets.sh
./deploy/04_instance.sh
```

This creates a $20 account-wide budget with 80% actual/100% forecast alerts, excluding credits/refunds; a VPC, two public subnets and internet gateway; DynamoDB tables/index, TTL and PITR; a private versioned S3 bucket; IAM policies, role and SSM signing key; and one EC2 host. There is no NAT gateway or load balancer. SSH is limited to the operator's current IP; HTTP/HTTPS are public. If the operator IP changes, update that one SSH rule before using rsync.

The role includes the application policy, CloudWatchAgentServerPolicy and AmazonSSMManagedInstanceCore. The last policy enables Session Manager. Instance bootstrap installs Docker, AWS CLI and the CloudWatch agent. Wait for bootstrap completion before deploying:

```bash
source deploy/state.env
ssh -i ~/.ssh/campuspulse-key.pem ubuntu@"$PUBLIC_IP" \
  'sudo cloud-init status --wait; test -f /var/lib/campuspulse-bootstrap-done'
./ops/deploy_app.sh
./deploy/05_monitoring.sh
```

Confirm the SNS subscription in your inbox. A working email address must be configured before running the monitoring script.

## 3. Host configuration

Connect with SSH, or AWS EC2 → instance → Connect → SSM Session Manager. Run on the **EC2 host**:

```bash
cd /opt/campuspulse
cp -n .env.example .env
nano .env
```

Set `BUCKET` to the created backup bucket. The other defaults match this project. `.env` contains resource names, not passwords. With Session Manager, use `sudo` if editing files owned by `ubuntu` requires it.

```bash
sudo docker compose up -d --build
sudo docker compose ps
sudo ./ops/configure_monitoring.sh
sudo ./ops/install_cron.sh
```

The backup cron job runs at 02:00 in the host timezone (Ubuntu AWS default UTC; confirm with `timedatectl`). Application logs must remain owned by UID 10001, as set in user-data.sh, because the API container runs as a non-root user. Root installs the backup cron so writing the backup log does not require changing application log ownership.

## 4. Create accounts

Run on the EC2 host after deploying this repository's application image:

```bash
sudo docker compose exec api python manage_user.py ops.admin --role admin --create
sudo docker compose exec api python manage_user.py front.desk --role staff --create
sudo docker compose exec api python manage_user.py sensor.fleet --role device --create
```

Each command prompts privately for a password and confirmation, then reads the saved hash back to verify it. `--create` refuses to overwrite an existing account. To reset an existing password, omit `--create`; the stored role must match the supplied role. The helper uses the existing GetItem/PutItem IAM permissions and conditional writes. Role changes require a separate deliberate administrative change.

`seed_users.py` is retained from the initial prototype and reads environment variables; it is not needed for this interactive workflow. Docker `--env-file` does not by itself pass arbitrary host variables into `docker compose exec`, so do not use the old guide's seeding command.

## 5. HTTPS and renewal

Create an A record for a domain you control pointing to this instance's public IPv4 address. The demonstrated domain is `cloud.learningtheory.xyz`; use your own hostname for another deployment. Confirm DNS resolves to the host and inbound ports 80/443 are allowed.

On the host:

```bash
sudo apt update
sudo apt install -y certbot
cd /opt/campuspulse
sudo ./ops/configure_https.sh cloud.learningtheory.xyz
```

The script mounts a shared ACME challenge folder and `/etc/letsencrypt` read-only into Nginx, adds the 443 port mapping, requests a certificate interactively, writes the TLS template and validates before reloading. It saves previous config files in a printed backup directory. The HTTP server redirects application requests to HTTPS while keeping `/.well-known/acme-challenge/` accessible. The HTTPS server proxies `/api/` to the internal API container; port 8000 remains unpublished.

An existing Compose override must match the supplied example; otherwise the script stops for a manual merge rather than replacing unrelated settings. Do not replace an already working live configuration merely to make it look identical to the template. The packaged template expresses the configuration verified manually on October 8; the packaging helper itself has not been run on the live host.

```bash
sudo certbot renew --dry-run --run-deploy-hooks
systemctl list-timers --all certbot.timer --no-pager
curl --fail https://cloud.learningtheory.xyz/api/health
curl -I http://cloud.learningtheory.xyz/
```

Expected: successful simulated renewal, Nginx validation/reload, scheduled timer, health JSON and HTTP 308 pointing to HTTPS. Keep the renewal path and DNS working. After EC2 stop/start the public IP can change; update DNS before expecting browser access or renewal to succeed.

## 6. Existing-host code updates

For the original operator checkout with correct ignored `deploy/state.env`, use `./ops/deploy_app.sh`. If starting from a new clone, recover the project's resource state first; do not create a duplicate stack. The update script synchronizes code, templates and `.env.example`, rebuilds containers, and preserves `.env`, logs, the active `dashboard/nginx.conf` and the host's Compose override. Nginx/template changes require deliberate application and validation. State/configuration for unrelated labs is outside this repository.

## 7. Verify and demonstrate

Run the simulator from your computer using the README command. Show a staff login denied access to alerts, an admin login with populated alerts, rising metrics in CloudWatch, the critical-event alarm history and its email. The validation record lists completed evidence and limits.
