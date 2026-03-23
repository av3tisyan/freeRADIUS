#!/usr/bin/env bash
# Wi-Fi 802.1X (EAP-TTLS/PAP, anonymous identity). Replace placeholders and run with sudo.

SSID="${SSID:-YOUR_WIFI_SSID}"
CA_CERT="${CA_CERT:-/path/to/ca.pem}"
IDENTITY="${IDENTITY:-YOUR_AD_USERNAME}"

sudo nmcli connection add type wifi con-name "WiFi-8021X" ssid "$SSID" \
  802-11-wireless-security.key-mgmt wpa-eap \
  802-1x.eap ttls \
  802-1x.phase2-auth pap \
  802-1x.identity "$IDENTITY" \
  802-1x.anonymous-identity "anonymous" \
  802-1x.ca-cert "$CA_CERT"
