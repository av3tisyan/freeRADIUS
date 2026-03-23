#!/bin/bash
#
# Remove all certificates and keys in the FreeRADIUS certs directory,
# then generate new CA and server certificate (with subjectAltName).
# Run as root on the server, e.g.:
#   sudo bash /etc/freeradius/3.0/certs/regenerate-certs.sh
#
set -e

CERTDIR="${1:-/etc/freeradius/3.0/certs}"
RADIUS_USER="${2:-freerad}"
RADIUS_GROUP="${RADIUS_USER}"

cd "$CERTDIR"
CONF="server.cnf"

echo "Working in $CERTDIR"

# Remove existing cert and key files (keep server.cnf and this script)
for f in server.pem server.key ca.pem ca.key server.crt server.csr ca.srl dh 2>/dev/null; do
  [ -f "$f" ] && rm -v "$f"
done

# CA subject (same org as server)
CA_SUBJ="/C=XX/ST=State/L=City/O=ExampleOrg/OU=RADIUS/CN=Example RADIUS CA"

# 1) Generate CA key and self-signed CA cert
echo "Generating CA key and certificate..."
openssl genrsa -out ca.key 2048
openssl req -new -x509 -key ca.key -out ca.pem -days 3650 -subj "$CA_SUBJ"

# 2) Generate server key
echo "Generating server key..."
openssl genrsa -out server.key 2048

# 3) Generate server CSR and cert (subjectAltName from xpextensions)
echo "Generating server CSR and certificate..."
openssl req -new -key server.key -out server.csr -config "$CONF"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 3650 \
  -extfile xpextensions -extensions xpserver_ext

# 4) Cleanup temporary files
rm -f server.csr ca.srl

# 5) Permissions: key files 640, certs 644, owned by freerad
echo "Setting ownership and permissions..."
chown "$RADIUS_USER:$RADIUS_GROUP" server.key server.pem ca.key ca.pem
chmod 640 server.key ca.key
chmod 644 server.pem ca.pem

echo "Done. New files: server.key, server.pem, ca.key, ca.pem"
echo "Restart FreeRADIUS (e.g. systemctl restart freeradius)."
