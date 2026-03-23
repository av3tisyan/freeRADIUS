#!/usr/bin/env bash
#
# Sync /etc/freeradius/3.0/ from this node to the second HA node.
# Run from cron on Node 1 (e.g. every 5–15 minutes).
# Copy to /usr/local/bin/ or similar, chmod +x, then add to crontab.
#
# Requires: SSH key auth to REMOTE_USER@REMOTE_HOST, and REMOTE_USER has
# passwordless sudo for rsync (and optionally for chown + systemctl restart).
#

set -e

# --- Configure these (or set in env) ---
REMOTE_USER="${REMOTE_USER:-deploy-user}"
REMOTE_HOST="${REMOTE_HOST:-192.168.200.22}"
LOCAL_PATH="${LOCAL_PATH:-/etc/freeradius/3.0/}"
REMOTE_PATH="${REMOTE_PATH:-/etc/freeradius/3.0/}"
LOG_FILE="${LOG_FILE:-/var/log/freeradius/rsync-sync.log}"

# If set to 1, after rsync run: ssh $REMOTE_USER@$REMOTE_HOST sudo chown -R freerad:freerad $REMOTE_PATH && sudo systemctl restart freeradius
RUN_REMOTE_RESTART="${RUN_REMOTE_RESTART:-0}"

# --- Do not edit below ---
DEST="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Prefer LOG_FILE; if we can't write there (e.g. run as freerad from systemd), use fallback so we don't fail service start
LOG_DIR=$(dirname "$LOG_FILE")
if [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR" 2>/dev/null; then
  if touch "$LOG_FILE" 2>/dev/null; then
    USE_LOG_FILE=1
  fi
fi
if [[ -z "${USE_LOG_FILE:-}" ]]; then
  LOG_FILE=/tmp/freeradius-rsync-sync.log
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE" 2>/dev/null || true
fi

log() {
  echo "[${TIMESTAMP}] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[${TIMESTAMP}] $*" >&2
}

log "Starting rsync to ${REMOTE_HOST}"

# When run from systemd ExecStartPost we must run as root (use sudo in the drop-in). If we can't read config, skip sync and don't fail the service.
if [[ ! -r "$LOCAL_PATH" ]]; then
  log "Skipping sync: cannot read ${LOCAL_PATH} (run this script as root or via sudo in ExecStartPost)."
  exit 0
fi

# Use SSH options so root (when run from systemd) can connect without pre-populated known_hosts.
# accept-new: add host key on first connection, then verify (no prompt).
export RSYNC_RSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

if rsync -az --delete --rsync-path="sudo rsync" "$LOCAL_PATH" "$DEST"; then
  log "Rsync completed successfully."
  EXIT=0
else
  log "Rsync failed with exit code $?"
  EXIT=1
fi

if [[ "$RUN_REMOTE_RESTART" == "1" ]] && [[ $EXIT -eq 0 ]]; then
  log "Running remote chown and freeradius restart..."
  if ssh $SSH_OPTS "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo chown -R freerad:freerad ${REMOTE_PATH} && sudo systemctl restart freeradius"; then
    log "Remote restart completed."
  else
    log "Remote restart failed."
    EXIT=1
  fi
fi

log "---"
# Always exit 0 so that when run from systemd ExecStartPost, a sync failure (e.g. Node 2 down, host key) does not prevent FreeRADIUS from starting. Check the log for failures.
exit 0
