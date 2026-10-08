#!/usr/bin/env bash
# Run on the Ubuntu host, not inside a container. Requires existing A record.
set -euo pipefail
DOMAIN="${1:?usage: sudo ./ops/configure_https.sh domain}"
[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && "$DOMAIN" == *.* ]] || {
  echo 'Use a lowercase DNS hostname, without scheme or path.' >&2; exit 1;
}
[[ "$EUID" -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
cd /opt/campuspulse
[[ -f dashboard/nginx.conf && -f docker-compose.yml ]]
command -v certbot >/dev/null || { echo 'Install certbot first: sudo apt install certbot' >&2; exit 1; }
# Preserve the current files for recovery. This script never resets the API or data.
BACKUP_DIR=$(mktemp -d /opt/campuspulse/https-backup.XXXXXX)
cp dashboard/nginx.conf "$BACKUP_DIR/nginx.conf"
if [[ -e docker-compose.override.yml ]]; then
  cp docker-compose.override.yml "$BACKUP_DIR/docker-compose.override.yml"
  cmp -s docker-compose.override.yml ops/https/compose.override.yml.example || {
    echo 'Existing Compose override differs. Merge the supplied example manually, then retry.' >&2
    exit 1
  }
fi
echo "Configuration backup: $BACKUP_DIR"
mkdir -p /var/www/certbot/.well-known/acme-challenge /etc/letsencrypt
cp ops/https/compose.override.yml.example docker-compose.override.yml
docker compose config --quiet
docker compose up -d --no-deps web
# Interactive Certbot prompt lets the operator supply email and accept CA terms.
certbot certonly --webroot -w /var/www/certbot --cert-name "$DOMAIN" -d "$DOMAIN"
# Write in place because nginx.conf is an individual bind-mounted file.
sed "s/__DOMAIN__/${DOMAIN}/g" ops/https/nginx.conf.template > /tmp/campuspulse-nginx-tls.conf
cat /tmp/campuspulse-nginx-tls.conf > dashboard/nginx.conf
if ! docker exec campuspulse-web nginx -t; then
  cat "$BACKUP_DIR/nginx.conf" > dashboard/nginx.conf
  echo 'TLS configuration failed validation; original Nginx file restored.' >&2
  exit 1
fi
docker exec campuspulse-web nginx -s reload
install -m 755 ops/https/reload-campuspulse /etc/letsencrypt/renewal-hooks/deploy/reload-campuspulse
systemctl enable --now certbot.timer
printf 'HTTPS configured: https://%s\nNext: sudo certbot renew --dry-run --run-deploy-hooks\n' "$DOMAIN"
