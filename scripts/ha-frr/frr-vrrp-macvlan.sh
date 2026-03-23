#!/bin/bash
# Create macvlan for FRR VRRP (RADIUS VIP 192.168.200.100).
# Copy to /usr/local/bin/frr-vrrp-macvlan.sh, set INTERFACE, chmod +x, run at boot before frr.
#
INTERFACE="${RADIUS_VRRP_INTERFACE:-ens18}"
VIP="192.168.200.100"
VRID="23"
MAC="00:00:5e:00:01:$(printf '%02x' "$VRID")"
IF="vrrp4-radius"

if ip link show "$IF" &>/dev/null; then
  exit 0
fi
ip link add "$IF" link "$INTERFACE" type macvlan mode bridge
ip link set dev "$IF" address "$MAC"
ip addr add "${VIP}/24" dev "$IF"
ip link set dev "$IF" up
