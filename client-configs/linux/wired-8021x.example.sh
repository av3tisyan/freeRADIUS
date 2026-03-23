#!/usr/bin/env bash
# Wired 802.1X (EAP-TTLS/PAP, anonymous identity). Replace placeholders and run with sudo.

INTERFACE="${INTERFACE:-eth0}"
CA_CERT="${CA_CERT:-/path/to/ca.pem}"
IDENTITY="${IDENTITY:-YOUR_AD_USERNAME}"

sudo nmcli connection add type ethernet con-name "Wired-8021X" ifname "$INTERFACE" \
  802-1x.auth-timeout 10 \
  802-1x.eap ttls \
  802-1x.phase2-auth pap \
  802-1x.identity "$IDENTITY" \
  802-1x.anonymous-identity "anonymous" \
  802-1x.ca-cert "$CA_CERT"
