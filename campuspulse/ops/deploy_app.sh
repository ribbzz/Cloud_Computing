#!/usr/bin/env bash
# Run on the operator's computer. Preserve the host's TLS configuration on redeploy.
set -euo pipefail
source "$(dirname "$0")/../deploy/00_config.sh"
need PUBLIC_IP
SRC="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${HOME}/.ssh/${KEY_NAME}.pem"
REMOTE="ubuntu@${PUBLIC_IP}"
rsync -az --delete \
  --exclude '.env' --exclude 'logs/' --exclude '__pycache__/' \
  --exclude 'nginx.conf' --exclude '*.before-*' \
  -e "ssh -i ${KEY} -o StrictHostKeyChecking=accept-new" \
  "${SRC}/app" "${SRC}/dashboard" "${SRC}/ops" \
  "${SRC}/docker-compose.yml" "${SRC}/.env.example" \
  "${SRC}/deploy/cloudwatch-agent.json" \
  "${REMOTE}:/opt/campuspulse/"
# Seed HTTP configuration only on a fresh host. Never replace a live TLS config.
rsync -az --ignore-existing -e "ssh -i ${KEY}" \
  "${SRC}/dashboard/nginx.conf" "${REMOTE}:/opt/campuspulse/dashboard/nginx.conf"
ssh -i "$KEY" "$REMOTE" \
  'cd /opt/campuspulse && docker compose up -d --build && docker compose ps'
echo "Deploy complete. Use your configured HTTPS domain after TLS setup."
