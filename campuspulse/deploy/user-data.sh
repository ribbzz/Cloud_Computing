#!/bin/bash
# Runs once, as root, the first time the instance boots.
# Everything here is part of the reproducible deployment: rebuilding the
# instance from scratch needs no manual clicking.
set -eux
exec > >(tee /var/log/campuspulse-bootstrap.log) 2>&1

apt-get update -y
apt-get upgrade -y

# --- Docker engine + compose plugin, from Docker's own repository ----------
apt-get install -y ca-certificates curl gnupg unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ubuntu

# --- AWS CLI v2, used by the nightly backup job ----------------------------
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# --- CloudWatch agent ------------------------------------------------------
curl -fsSL https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  -o /tmp/cwagent.deb
dpkg -i -E /tmp/cwagent.deb
rm -f /tmp/cwagent.deb

# --- unattended security updates ------------------------------------------
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# --- application directory the deploy step copies into --------------------
mkdir -p /opt/campuspulse/logs
chown -R ubuntu:ubuntu /opt/campuspulse
# the api container runs as uid 10001 (appuser, see app/Dockerfile).
# the ./logs bind mount must be writable by that uid, not by ubuntu.
chown 10001:10001 /opt/campuspulse/logs

touch /var/lib/campuspulse-bootstrap-done
echo "bootstrap complete"
