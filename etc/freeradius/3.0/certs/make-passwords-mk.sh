#!/bin/sh
#
# Generate passwords.mk with correct CA_DEFAULT_DAYS (only from the line
# that starts with "default_days ", not default_crl_days). Run this
# before "./bootstrap" or "make" if you get:
#   -days ' -config ... Syntax error: Unterminated quoted string
#
# Usage: cd /etc/freeradius/3.0/certs && sudo bash make-passwords-mk.sh
#
set -e
cd "$(dirname "$0")"

for f in server.cnf ca.cnf client.cnf inner-server.cnf; do
  [ -f "$f" ] || { echo "Missing $f"; exit 1; }
done

# Use grep '^default_days ' so we get only the CA validity, not default_crl_days
CA_DAYS="$(grep '^default_days ' ca.cnf | sed 's/.*=//;s/^ *//;s/ *$//')"
[ -n "$CA_DAYS" ] || CA_DAYS="3650"

# Default used for all pass phrases so Make never gets empty pass: (breaks client.p12 etc.)
DEFAULT_PASS="whatever"

get_pass() { grep 'output_password' "$1" 2>/dev/null | sed 's/.*=//;s/^ *//;s/ *$//;s/'"'"'//g' | head -1; }
get_email() { grep 'emailAddress' "$1" 2>/dev/null | grep '@' | sed 's/.*=//;s/^ *//;s/ *$//' | head -1; }

PASSWORD_SERVER="$(get_pass server.cnf)"
PASSWORD_CA="$(get_pass ca.cnf)"
PASSWORD_INNER="$(get_pass inner-server.cnf)"
PASSWORD_CLIENT="$(get_pass client.cnf)"
USER_NAME="$(get_email client.cnf)"

[ -n "$PASSWORD_SERVER" ] || PASSWORD_SERVER="$DEFAULT_PASS"
[ -n "$PASSWORD_CA" ] || PASSWORD_CA="$DEFAULT_PASS"
[ -n "$PASSWORD_INNER" ] || PASSWORD_INNER="$DEFAULT_PASS"
[ -n "$PASSWORD_CLIENT" ] || PASSWORD_CLIENT="$DEFAULT_PASS"
[ -n "$USER_NAME" ] || USER_NAME="user@example.com"

# Ensure no newlines or empty; Make expands these as pass:$(VAR)
PASSWORD_SERVER="$(echo "$PASSWORD_SERVER" | tr -d '\n')"
PASSWORD_CA="$(echo "$PASSWORD_CA" | tr -d '\n')"
PASSWORD_INNER="$(echo "$PASSWORD_INNER" | tr -d '\n')"
PASSWORD_CLIENT="$(echo "$PASSWORD_CLIENT" | tr -d '\n')"
[ -n "$PASSWORD_SERVER" ] || PASSWORD_SERVER="$DEFAULT_PASS"
[ -n "$PASSWORD_CA" ] || PASSWORD_CA="$DEFAULT_PASS"
[ -n "$PASSWORD_INNER" ] || PASSWORD_INNER="$DEFAULT_PASS"
[ -n "$PASSWORD_CLIENT" ] || PASSWORD_CLIENT="$DEFAULT_PASS"

cat > passwords.mk << EOF
PASSWORD_SERVER	= '${PASSWORD_SERVER}'
PASSWORD_INNER	= '${PASSWORD_INNER}'
PASSWORD_CA	= '${PASSWORD_CA}'
PASSWORD_CLIENT	= '${PASSWORD_CLIENT}'
USER_NAME	= '${USER_NAME}'
CA_DEFAULT_DAYS  = '${CA_DAYS}'
EOF

chmod 644 passwords.mk
# So Make won't rebuild passwords.mk (its rule would overwrite with broken values)
touch passwords.mk
echo "Created passwords.mk (CA_DEFAULT_DAYS=${CA_DAYS}). Run ./bootstrap or make client now."
