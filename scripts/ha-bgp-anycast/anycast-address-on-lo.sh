#!/bin/bash
# Add BGP anycast address 192.168.200.100/32 on loopback (both nodes).
# Copy to /usr/local/bin/, chmod +x, run at boot via systemd.
#
ANYCAST="${RADIUS_ANYCAST_IP:-192.168.200.100}"
if ip addr show lo | grep -q "${ANYCAST}/32"; then
  exit 0
fi
ip addr add "${ANYCAST}/32" dev lo
exit 0
