#!/bin/bash
#
# FreeRADIUS EAP cert renewal: check server cert expiry and renew if within threshold.
# Uses renew-server-cert-only.sh (keeps CA; no WiFi client updates). Run as root via cron or systemd timer.
#
# Usage: renew-certs-if-needed.sh [ days_before_expiry ]
#   Default: renew if server cert expires within 60 days.
#
set -e

CERTDIR="${CERTDIR:-/etc/freeradius/3.0/certs}"
SERVER_CERT="${CERTDIR}/server.pem"
[ -f "$SERVER_CERT" ] || SERVER_CERT="${CERTDIR}/server.crt"
DAYS_THRESHOLD="${1:-60}"
RADIUS_USER="${RADIUS_USER:-freerad}"
LOG_TAG="freeradius-cert-renew"

log() { echo "$(date -Iseconds) [$LOG_TAG] $*"; logger -t "$LOG_TAG" "$*" 2>/dev/null || true; }

if [ ! -f "$SERVER_CERT" ]; then
  log "ERROR: Server cert not found ($SERVER_CERT). Skipping."
  exit 1
fi

EXPIRY_EPOCH=$(openssl x509 -enddate -noout -in "$SERVER_CERT" | cut -d= -f2)
EXPIRY_SEC=$(date -d "$EXPIRY_EPOCH" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY_EPOCH" +%s 2>/dev/null)
NOW_SEC=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_SEC - NOW_SEC) / 86400 ))

if [ "$DAYS_LEFT" -gt "$DAYS_THRESHOLD" ]; then
  log "Server cert valid for $DAYS_LEFT days (threshold $DAYS_THRESHOLD). No renewal."
  exit 0
fi

log "Server cert expires in $DAYS_LEFT days. Renewing server cert (keeping CA)..."

RENEW_SCRIPT="${CERTDIR}/renew-server-cert-only.sh"
if [ ! -x "$RENEW_SCRIPT" ]; then
  log "ERROR: $RENEW_SCRIPT not found or not executable."
  exit 1
fi

"$RENEW_SCRIPT" "$CERTDIR" "$RADIUS_USER" || { log "ERROR: renew-server-cert-only.sh failed"; exit 1; }

if systemctl is-active -q freeradius 2>/dev/null; then
  systemctl restart freeradius
  log "FreeRADIUS restarted."
else
  log "FreeRADIUS not running (systemd). Start it manually if needed."
fi

log "Renewal complete."
exit 0
