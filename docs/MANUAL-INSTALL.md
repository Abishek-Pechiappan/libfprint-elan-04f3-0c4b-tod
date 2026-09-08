# Manual installation — the long way

This is the full step-by-step version of the install, for people who want to
see every command, or for when [`scripts/install.sh`](../scripts/install.sh)
blows up and you need to finish by hand.

If you just want it working, start at the [README](../README.md) instead.

Want to know *why* any of this is necessary? That's in
[BACKGROUND.md](BACKGROUND.md).

---

## Installation — step by step

### Step 1: Confirm your device

```bash
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] && echo "$d : $(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/product 2>/dev/null)"
done
```

You're looking for something like:
```
/sys/bus/usb/devices/3-6/ : 04f3:0c4b ELAN:Fingerprint
```

If your ID isn't `04f3:0c4b`, this guide may not apply — see [BACKGROUND.md](BACKGROUND.md) for
how to check whether your device is already (actually) supported.

### Step 2: Try the proprietary driver via AUR (it will fail — that's the plan)

```bash
yay -S libfprint-2-tod1-elan
```

This pulls in `libfprint-tod-git` as a dependency and tries to build it. **It
will fail**, dramatically, with:

```
/usr/bin/ld: libfprint/tod/libfprint-2-tod.so.1: no symbol version section
for versioned symbol `fpi_ssm_new_full@LIBFPRINT_TOD_1_1.92'
/usr/bin/ld: final link failed
```

Don't panic — this is a known bug in `libfprint-tod-git`'s version script,
made worse by Arch's default LTO settings (full nerdy explanation in
[BACKGROUND.md](BACKGROUND.md)). Steps 3–5 fix it.

### Step 3: Patch the cached source

yay extracts the source to `~/.cache/yay/libfprint-tod-git/src/libfprint`.
Apply the included patch there:

```bash
cd ~/.cache/yay/libfprint-tod-git/src/libfprint
git apply ~/elan-fingerprint-fix/patches/0001-fix-duplicate-versioned-symbols-in-tod-version-script.patch
```

(If `git apply` complains, `patch -p1 < /path/to/patch` works too. It's not
picky about how it gets there.)

### Step 4: Disable LTO and rebuild

The patch alone isn't enough — Arch's `-flto=auto` produces "slim LTO" object
files that strip out the symbol-versioning info the version script needs.
Strip it from the already-generated build files and rebuild:

```bash
cd ~/.cache/yay/libfprint-tod-git/src/build
sed -i 's/-flto=auto//g' build.ninja
ninja -t clean
ninja
```

This should now finish successfully (214/214 targets — yes, I counted).

### Step 5: Package and install `libfprint-tod-git` manually

`makepkg` has no idea you just rebuilt everything behind its back, so we
package it ourselves like absolute professionals:

```bash
mkdir -p /tmp/libfprint-tod-pkgdir
cd ~/.cache/yay/libfprint-tod-git/src/build
meson install -C . --destdir /tmp/libfprint-tod-pkgdir

cd /tmp/libfprint-tod-pkgdir
cat > .PKGINFO <<'EOF'
pkgname = libfprint-tod-git
pkgbase = libfprint-tod-git
pkgver = 1.95.1+tod1-1
pkgdesc = Library for fingerprint readers - TOD version (LTO disabled)
url = https://fprint.freedesktop.org/
arch = x86_64
license = LGPL
provides = libfprint=1.95.1
provides = libfprint-tod
provides = libfprint-2.so
provides = libfprint-2.so=2-64
provides = libfprint-2-tod.so
conflict = libfprint
group = fprint
depend = libgusb>=0.3.0
depend = nss
depend = pixman
depend = libgudev
EOF

fakeroot tar --zstd -cf ../libfprint-tod-git-1.95.1+tod1-1-x86_64.pkg.tar.zst .PKGINFO usr
sudo pacman -U ../libfprint-tod-git-1.95.1+tod1-1-x86_64.pkg.tar.zst
```

pacman will probably complain about a conflict with the official `libfprint`
and ask to remove it — **say yes**, that's the whole point. The `provides`
lines above (especially `libfprint-2.so=2-64`) keep `fprintd` and friends from
having an existential crisis afterwards.

> **Why `provides = libfprint-2.so=2-64`?** `fprintd` depends on
> `libfprint-2.so=2-64`. Our patched build still exports the `LIBFPRINT_2.0.0`
> version node (full backwards compatibility), so this isn't a lie — unlike
> the `elan` driver from earlier.

### Step 6: Install the proprietary ELAN TOD driver

Now that `libfprint-tod` exists, install the actual driver blob:

```bash
git clone https://github.com/TonyHoyle/libfprint-2-tod1-elan /tmp/libfprint-2-tod1-elan-src
mkdir -p /tmp/libfprint-2-tod1-elan/usr/lib/libfprint-2/tod-1 /tmp/libfprint-2-tod1-elan/usr/lib/udev/rules.d
cp /tmp/libfprint-2-tod1-elan-src/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod1-elan.so /tmp/libfprint-2-tod1-elan/usr/lib/libfprint-2/tod-1/
cp /tmp/libfprint-2-tod1-elan-src/lib/udev/rules.d/60-libfprint-2-tod1-elan.rules /tmp/libfprint-2-tod1-elan/usr/lib/udev/rules.d/

cd /tmp/libfprint-2-tod1-elan
cat > .PKGINFO <<'EOF'
pkgname = libfprint-2-tod1-elan
pkgbase = libfprint-2-tod1-elan
pkgver = 0.0.1-2
pkgdesc = Proprietary driver for the Elan 04f3:0c4b fingerprint reader, from Lenovo E14 Gen 4 Ubuntu driver.
url = https://github.com/TonyHoyle/libfprint-2-tod1-elan
arch = x86_64
license = custom
group = fprint
depend = libfprint-tod
depend = libcrypto.so=1.1
EOF

fakeroot tar --zstd -cf ../libfprint-2-tod1-elan-0.0.1-2-x86_64.pkg.tar.zst .PKGINFO usr
sudo pacman -U ../libfprint-2-tod1-elan-0.0.1-2-x86_64.pkg.tar.zst
```

`libcrypto.so=1.1` comes from `openssl-1.1` — grab it first if you don't have
it: `sudo pacman -S openssl-1.1`.

### Step 7: Fix the udev rule that the package forgot to enable, then reload udev & restart fprintd

Here's a fun one. `libfprint-2-tod1-elan` ships its udev rule
(`/usr/lib/udev/rules.d/60-libfprint-2-tod1-elan.rules`) with **every single
line commented out**:

```
# SUBSYSTEM=="usb", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="0c4b", ATTRS{dev}=="*", TEST=="power/control", ATTR{power/control}="auto", MODE="0660", GROUP="plugdev"
# SUBSYSTEM=="usb", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="0c4b", ENV{LIBFPRINT_DRIVER}="Elan Fingerprint Sensor"
```

That second line is the whole point of this driver — it's the
`LIBFPRINT_DRIVER` hint that tells libfprint "use the TOD driver for this
device, not the lying built-in `elan` one." With it commented out, libfprint
falls back to probing the device with the broken `elan` driver whenever it
actually has to *do* something with the sensor.

The annoying part: this doesn't show up in Step 8 the way you'd expect.
`fprintd-list` and even `fprintd-enroll`/`fprintd-verify` run by hand right
after install can look totally fine — those are mostly reading stored data,
not talking to hardware in real time. It's PAM-driven verification (SDDM
greeter, `sudo`, `hyprlock`) that hangs for a full ~30 seconds and then
silently falls back to your password, with `journalctl -u fprintd` quietly
screaming `g_usb_device_bulk_transfer_finish failed: transfer timed out` —
the wrong driver got probed for the live scan.

Fix it with an **override** file in `/etc/udev/rules.d/` (don't touch the
package's copy in `/usr/lib/udev/rules.d/` — pacman will just stomp it back
to "commented out" on the next update):

```bash
sudo tee /etc/udev/rules.d/60-libfprint-2-tod1-elan.rules > /dev/null <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="0c4b", ATTRS{dev}=="*", TEST=="power/control", ATTR{power/control}="auto", MODE="0660", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="04f3", ATTRS{idProduct}=="0c4b", ENV{LIBFPRINT_DRIVER}="Elan Fingerprint Sensor"
EOF
```

Then reload udev and restart fprintd like you were always going to:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
sudo systemctl restart fprintd
```

### Step 8: Enroll & verify

Moment of truth:

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
fprintd-list $USER
```

`fprintd-list` should show:
```
Fingerprints for user <you> on ELAN Fingerprint Sensor (press):
 - #0: right-index-finger
```

If you previously got "ElanTech Fingerprint Sensor" with a protocol error —
that was the lying driver. **"ELAN Fingerprint Sensor"** (no "Tech") means the
TOD driver is in charge now and actually telling the truth.

If `fprintd-verify` instead just sits there for ~30 seconds and times out
without ever reading your finger, go back to Step 7 — the udev override rule
is missing or wasn't reloaded. This is also exactly what causes the
"fingerprint prompt shows up in `sudo`/SDDM/`hyprlock` but always falls back
to your password" symptom from Step 10.

### Step 9: Install a polkit agent (or enrollment won't even start)

If `fprintd-enroll` immediately throws:
```
EnrollStart failed: GDBus.Error:net.reactivated.Fprint.Error.PermissionDenied
```
...you need a polkit authentication agent running. On a full desktop
environment (GNOME, KDE, etc.) one is already running — skip to Step 10. On
Hyprland (or any other "I built my desktop from scratch and now I must suffer
for it" WM):

```bash
yay -S hyprpolkitagent
```

Then add it to your Hyprland autostart (e.g. in `hyprland.lua`, inside
`hl.on("hyprland.start", function() ... end)`):

```lua
hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")
```

Restart Hyprland (or just run that binary once) before retrying Step 8.

### Step 10: PAM integration (sudo / login / hyprlock)

To let your finger replace your password for `sudo`, login, and `hyprlock`,
add `pam_fprintd.so` as the first `auth` line in `/etc/pam.d/system-auth`:

```bash
sudo sed -i '/^auth.*pam_faillock.so.*preauth/i auth       sufficient                  pam_fprintd.so' /etc/pam.d/system-auth
```

`sufficient` means: a successful scan gets you in immediately; on failure or
timeout it politely falls back to asking for your password (and doesn't count
against `pam_faillock`'s lockout, so a shy sensor won't lock you out of your
own machine).

Test it:

```bash
sudo -k && sudo true     # scan finger when prompted
fprintd-verify            # sanity check, no PAM involved
hyprlock                  # Super+L, then touch sensor to unlock
```

If `hyprlock` unlocks with your fingerprint, congratulations — you have
successfully turned a $5 sensor that the manufacturer half-implemented into a
working biometric lock through sheer spite.
