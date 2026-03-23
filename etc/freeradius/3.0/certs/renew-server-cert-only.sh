#!/bin/bash
#
# Renew only the FreeRADIUS server cert; keep existing CA (ca.pem, ca.key).
# WiFi clients keep using the same ca.pem – no client updates.
# Run as root: sudo bash renew-server-cert-only.sh
#
set -e

CERTDIR="${1:-/etc/freeradius/3.0/certs}"
RADIUS_USER="${2:-freerad}"
RADIUS_GROUP="${RADIUS_USER}"

cd "$CERTDIR"

for f in ca.pem ca.key; do
  [ -f "$f" ] || { echo "Missing $f. Keep existing CA; cannot renew server-only."; exit 1; }
done

# Remove only server cert/key (not CA)
for f in server.pem server.key server.crt server.csr; do
  [ -f "$f" ] && rm -v "$f"
done

echo "Generating new server key and certificate (existing CA)..."
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -config server.cnf
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 3650 \
  -extfile xpextensions -extensions xpserver_ext
rm -f server.csr ca.srl

chown "$RADIUS_USER:$RADIUS_GROUP" server.key server.pem
chmod 640 server.key
chmod 644 server.pem

echo "Server cert renewed. Restart FreeRADIUS: systemctl restart freeradius"
