#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo " ELAN 04f3:0c4b fingerprint driver installer"
echo "=================================================="
echo

"$SCRIPT_DIR/01-check-device.sh"
"$SCRIPT_DIR/02-prereqs.sh"
"$SCRIPT_DIR/03-build-libfprint-tod.sh"
"$SCRIPT_DIR/04-build-elan-driver.sh"
"$SCRIPT_DIR/05-finish.sh"

echo
echo "All done!"
