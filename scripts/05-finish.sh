#!/usr/bin/env bash
set -euo pipefail

echo "==> Fixing the udev rule the package ships commented out..."
sudo tee /etc/udev/rules.d/60-libfprint-2-tod1-elan.rules > /dev/null <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="0c4b", ATTRS{dev}=="*", TEST=="power/control", ATTR{power/control}="auto", MODE="0660", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="0c4b", ENV{LIBFPRINT_DRIVER}="Elan Fingerprint Sensor"
EOF

echo "==> Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
sudo systemctl restart fprintd

echo
echo "==> Driver installation complete."
echo

read -rp "Enroll a fingerprint now (right-index-finger)? [y/N] " ans
case "$ans" in
    [yY]*)
        fprintd-enroll -f right-index-finger
        fprintd-verify
        fprintd-list "$USER"
        ;;
    *)
        echo "Skipping enrollment. Run later with: fprintd-enroll -f right-index-finger"
        ;;
esac

cat <<'EOF'

==============================================================
Driver setup is done. Two OPTIONAL steps from the README were
NOT applied automatically (they touch system auth / personal
config files - review before applying):

--- Step 9: Polkit agent ---
Needed if fprintd-enroll/verify fails with PermissionDenied,
typically on bare WMs like Hyprland (DEs usually have one already):

  yay -S hyprpolkitagent

Then add to your Hyprland autostart (e.g. hyprland.lua, inside
hl.on("hyprland.start", function() ... end)):

  hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")

--- Step 10: PAM integration (fingerprint for sudo/login/hyprlock) ---

  sudo sed -i '/^auth.*pam_faillock.so.*preauth/i auth       sufficient                  pam_fprintd.so' /etc/pam.d/system-auth

Test with:
  sudo -k && sudo true
  fprintd-verify
  hyprlock

See the main README for full details on both steps.
==============================================================
EOF
