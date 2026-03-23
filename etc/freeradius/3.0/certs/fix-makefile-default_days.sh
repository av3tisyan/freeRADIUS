#!/bin/sh
#
# Fix the FreeRADIUS certs Makefile so "grep default_days" only matches the
# CA default_days line (not default_crl_days). Without this, passwords.mk
# gets "3650\n30" and the openssl -days argument breaks (syntax error).
#
# Run once before first "make" or "./bootstrap":
#   sudo bash fix-makefile-default_days.sh
#
set -e
cd "$(dirname "$0")"
MAKEFILE="${1:-Makefile}"

if [ ! -f "$MAKEFILE" ]; then
  echo "Usage: $0 [path/to/Makefile]"
  echo "  Default: ./Makefile"
  exit 1
fi

# Only match line that starts with "default_days " so default_crl_days is excluded
if grep -q 'grep default_days ca.cnf' "$MAKEFILE"; then
  sed -i.bak 's/grep default_days ca.cnf/grep "^default_days " ca.cnf/g' "$MAKEFILE"
  echo "Patched $MAKEFILE (backup: ${MAKEFILE}.bak). You can run make or ./bootstrap now."
else
  echo "Makefile already patched or format unknown; no change."
fi
