#!/usr/bin/env bash
#
# Restart FreeRADIUS on this node; if the service comes up OK, sync config
# to the second HA node. Use this after changing config so Node 2 gets
# updates only when Node 1 is running normally.
#
# Requires: sync-freeradius-to-node2.sh in the same directory or in PATH.
# Run with sudo.
#

set -e

SERVICE_NAME="${RADIUS_SERVICE_NAME:-freeradius}"
CONFIG_TEST="${RADIUS_CONFIG_TEST:-1}"
WAIT_AFTER_RESTART="${RADIUS_SYNC_WAIT_AFTER_RESTART:-3}"
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
SYNC_SCRIPT="${SYNC_SCRIPT:-${SCRIPT_DIR}/sync-freeradius-to-node2.sh}"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  SYNC_SCRIPT=$(command -v sync-freeradius-to-node2.sh || true)
fi
if [[ ! -x "$SYNC_SCRIPT" ]]; then
  echo "restart-freeradius-and-sync: sync script not found. Set SYNC_SCRIPT or install sync-freeradius-to-node2.sh." >&2
  exit 1
fi

echo "Testing config (radiusd -C)..."
if ! radiusd -C -x -D /etc/freeradius/3.0 2>/dev/null; then
  echo "Config test failed. Fix config before restart. Aborting sync." >&2
  exit 1
fi

echo "Restarting ${SERVICE_NAME}..."
systemctl restart "$SERVICE_NAME"

echo "Waiting ${WAIT_AFTER_RESTART}s for service to settle..."
sleep "$WAIT_AFTER_RESTART"

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  echo "Service is not active after restart. Aborting sync." >&2
  exit 1
fi

echo "Service is running. Syncing config to Node 2..."
exec "$SYNC_SCRIPT"
