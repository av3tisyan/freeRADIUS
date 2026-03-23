# FreeRADIUS Certificate Renewal – Automated Guide

This guide covers **automated renewal** of the EAP TLS certificates (CA + server) used by FreeRADIUS for EAP-TTLS WiFi. It assumes certs are in `/etc/freeradius/3.0/certs/` and you use **regenerate-certs.sh** (or the Makefile) to create them.

---

## 1. When to renew

| Cert | Typical validity | Renew when |
|------|------------------|------------|
| **ca.pem** | 10 years (3650 days) | Only if you do a full CA rotation |
| **server.pem** / **server.crt** | 10 years (3650 days) | Before expiry (e.g. 30–60 days) |

- **Server cert only:** Renew the server cert but keep the same CA. WiFi clients already have **ca.pem** installed; no client changes.
- **Full regenerate (new CA):** If you run `regenerate-certs.sh` or `make destroycerts && make server`, you get a **new CA**. You must redistribute **ca.pem** to all WiFi clients and update 802.1X profiles.

For automation, the recommended approach is **renew server cert only** (same CA) so no client updates are needed. Use **renew-server-cert-only.sh** for that; use **regenerate-certs.sh** only when you intentionally rotate the CA.

---

## 2. Renewal script (expiry check + optional regenerate)

Use a script that:

1. Checks server cert expiry (e.g. days until expiry).
2. If within threshold (e.g. 60 days), runs **renew-server-cert-only.sh** (keeps CA; no client change) or optionally **regenerate-certs.sh** (full replace).
3. Restarts FreeRADIUS and optionally syncs to HA peer.

Save as `/etc/freeradius/3.0/certs/renew-certs-if-needed.sh`.

```bash
#!/bin/bash
#
# FreeRADIUS EAP cert renewal: check server cert expiry and regenerate if within threshold.
# Run as root (cron or systemd timer). Uses regenerate-certs.sh for full CA+server replace.
#
# Usage: renew-certs-if-needed.sh [ days_before_expiry ]
#   Default: renew if server cert expires within 60 days.
#
set -e

CERTDIR="${CERTDIR:-/etc/freeradius/3.0/certs}"
SERVER_CERT="${CERTDIR}/server.pem"
# Fallback if you use server.crt instead of server.pem
[ -f "$SERVER_CERT" ] || SERVER_CERT="${CERTDIR}/server.crt"
DAYS_THRESHOLD="${1:-60}"
RADIUS_USER="${RADIUS_USER:-freerad}"
LOG_TAG="freeradius-cert-renew"

log() { echo "$(date -Iseconds) [$LOG_TAG] $*"; logger -t "$LOG_TAG" "$*"; }

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

# Use server-only renewal so WiFi clients keep the same ca.pem.
RENEW_SCRIPT="${CERTDIR}/renew-server-cert-only.sh"
if [ ! -x "$RENEW_SCRIPT" ]; then
  log "ERROR: $RENEW_SCRIPT not found or not executable."
  exit 1
fi

"$RENEW_SCRIPT" "$CERTDIR" "$RADIUS_USER" || { log "ERROR: renew-server-cert-only.sh failed"; exit 1; }

# Restart FreeRADIUS so it loads the new certs
if systemctl is-active -q freeradius 2>/dev/null; then
  systemctl restart freeradius
  log "FreeRADIUS restarted."
else
  log "FreeRADIUS not running (systemd). Start it manually if needed."
fi

# Optional: sync certs to HA peer (adjust for your node names and paths)
# SYNC_HOST="freeradius-node-b"
# rsync -az "${CERTDIR}/server.key" "${CERTDIR}/server.pem" "${CERTDIR}/ca.pem" "${CERTDIR}/ca.key" "$SYNC_HOST:${CERTDIR}/"
# ssh "$SYNC_HOST" "systemctl restart freeradius"

log "Renewal complete."
exit 0
```

- **Server cert file:** Script checks `server.pem` first, then `server.crt`. Adjust if your EAP config uses a different path.
- **Threshold:** Default 60 days; override with first argument, e.g. `renew-certs-if-needed.sh 30`.
- **HA:** Uncomment and set `SYNC_HOST` and paths if you want to push certs to the other node and restart there.

---

## 3. Make script executable

On the server:

```bash
sudo chmod +x /etc/freeradius/3.0/certs/renew-certs-if-needed.sh
```

---

## 4. Automate with cron

Run the script once a month (or weekly). Run as root so it can write to the cert dir and restart the service.

```bash
sudo crontab -e
```

Add (e.g. first day of the month at 2:00 AM):

```cron
0 2 1 * * /etc/freeradius/3.0/certs/renew-certs-if-needed.sh 60 >> /var/log/freeradius/cert-renew.log 2>&1
```

Or weekly (Sunday 2:00 AM):

```cron
0 2 * * 0 /etc/freeradius/3.0/certs/renew-certs-if-needed.sh 60 >> /var/log/freeradius/cert-renew.log 2>&1
```

Create the log file and allow the script to append:

```bash
sudo touch /var/log/freeradius/cert-renew.log
sudo chown root:root /var/log/freeradius/cert-renew.log
```

---

## 5. Automate with systemd timer (alternative to cron)

**Service file** – `/etc/systemd/system/freeradius-cert-renew.service`:

```ini
[Unit]
Description=FreeRADIUS EAP certificate renewal (if near expiry)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/freeradius/3.0/certs/renew-certs-if-needed.sh 60
Environment=CERTDIR=/etc/freeradius/3.0/certs RADIUS_USER=freerad
# Optional: restrict permissions
# ReadWritePaths=/etc/freeradius/3.0/certs
# NoNewPrivileges=yes
```

**Timer file** – `/etc/systemd/system/freeradius-cert-renew.timer`:

```ini
[Unit]
Description=Run FreeRADIUS cert renewal monthly

[Timer]
OnCalendar=monthly
OnCalendar=*-*-01 02:00:00
Persistent=yes

[Install]
WantedBy=timers.target
```

Enable and start the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable freeradius-cert-renew.timer
sudo systemctl start freeradius-cert-renew.timer
sudo systemctl list-timers --all | grep freeradius
```

---

## 6. Server-only renewal script (included)

**renew-server-cert-only.sh** in the certs directory renews only the server cert and keeps the existing CA:

- Leaves `ca.pem` and `ca.key` in place.
- Generates new `server.key` and `server.pem` (signed by existing CA, with subjectAltName from xpextensions).
- No need to redistribute ca.pem to WiFi clients.

Make it executable and call it from cron or the timer (as in the `renew-certs-if-needed.sh` example above):

```bash
sudo chmod +x /etc/freeradius/3.0/certs/renew-server-cert-only.sh
```

---

## 7. Checklist

| Step | Action |
|------|--------|
| 1 | Deploy `regenerate-certs.sh`, `renew-server-cert-only.sh`, and `renew-certs-if-needed.sh` under `/etc/freeradius/3.0/certs/`. |
| 2 | Ensure `server.cnf` and `xpextensions` are present so the new server cert has subjectAltName. |
| 3 | Make scripts executable: `chmod +x .../renew-certs-if-needed.sh` (and optional server-only script). |
| 4 | Choose cron or systemd timer and install it (monthly or weekly, 60-day threshold). |
| 5 | If HA: add rsync/ssh step in the script to sync certs to the other node and restart there. |
| 6 | (Optional) Monitor `/var/log/freeradius/cert-renew.log` or syslog for “Renewal complete” or errors. |

---

## 8. Important notes

- **Full regenerate** (new CA): All WiFi clients must get the new **ca.pem** and update their 802.1X profile. Prefer **server-only** renewal for automation.
- **Regenerate script:** `regenerate-certs.sh` replaces both CA and server cert. For automation you can either call it only when you intend to rotate the CA (and then push new ca.pem via MDM/GPO), or use a **server-only** renewal script and call that from cron/timer.
- **Backup:** Before renewing, backup `server.key`, `server.pem`, `ca.pem`, and `ca.key`; the script overwrites them.
- **Reload vs restart:** FreeRADIUS typically needs a **restart** to pick up new certs; a simple reload is often not enough. The script uses `systemctl restart freeradius`.
