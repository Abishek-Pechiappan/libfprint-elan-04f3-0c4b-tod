#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="04f3:0c4b"
found=0

for d in /sys/bus/usb/devices/*/; do
    if [ -f "${d}idVendor" ] && [ -f "${d}idProduct" ]; then
        vid=$(cat "${d}idVendor")
        pid=$(cat "${d}idProduct")
        if [ "${vid}:${pid}" = "$DEVICE_ID" ]; then
            found=1
            product=$(cat "${d}product" 2>/dev/null || echo "unknown")
            echo "Found device: ${d} : ${vid}:${pid} ${product}"
        fi
    fi
done

if [ "$found" -eq 0 ]; then
    echo "WARNING: No USB device with ID $DEVICE_ID found."
    echo "This script and patch are specific to the ELAN $DEVICE_ID fingerprint sensor."
    read -rp "Continue anyway? [y/N] " ans
    case "$ans" in
        [yY]*) ;;
        *) echo "Aborting."; exit 1 ;;
    esac
fi
