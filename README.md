# Getting the ELAN 04f3:0c4b Fingerprint Reader (Arch + Hyprland)

So you bought a laptop with a fingerprint reader, you're running Arch like a
responsible adult, and `fprintd-enroll` just... doesn't work. Cool. Cool cool
cool. This repo is for the ELAN sensor with USB ID **`04f3:0c4b`**, found on
some Lenovo laptops (ThinkPads etc.), and it documents the slightly unhinged
process of making it actually work.

## TL;DR

`libfprint`'s built-in `elan` driver *claims* it supports `04f3:0c4b`. It
does not. It lies. What you actually get is:

```
Enroll result: enroll-disconnected
```

and `journalctl -u fprintd` cheerfully informs you that "the driver
encountered a protocol error with the device" — which is system-log-speak for
"these two pieces of software have never met and have no idea what to say to
each other."

The open-source `elan` driver just doesn't speak this device's protocol yet —
nobody's reverse-engineered it for `libfprint` proper. So until that happens,
the workaround is to use Lenovo's proprietary **TOD (Touch OEM Driver)** blob
instead. Its dependency, `libfprint-tod-git` (AUR), *also* doesn't build out
of the box — it has its own bug. So this repo gives you:

1. A patch + build workaround for `libfprint-tod-git`.
2. Steps to install the proprietary ELAN TOD driver + udev rule.
3. PAM/polkit setup so your finger can unlock `sudo`, login, and `hyprlock`.

If your device ID is **not** `04f3:0c4b` — sorry, wrong README. Check the
"Background" section for pointers, then go find your own rabbit hole.

> **Tested on**: Arch Linux, `libfprint-tod-git` v1.95.1+tod1
> (`3v1n0/libfprint#tod` branch), as of June 2026. If `yay -S
> libfprint-2-tod1-elan` just works for you out of the box now, the upstream
> bug has probably been fixed — congrats, close this tab and enjoy your
> fingerprint reader. Otherwise, welcome, you'll fit right in here.

## Contents

- [Quick install (script)](#quick-install-script)
- [Prerequisites](#prerequisites)
- [Installation — step by step](#installation--step-by-step)
- [Background](#background)
- [Caveats / maintenance](#caveats--maintenance)
- [Acknowledgements](#acknowledgements)

---

## Quick install (script)

If you'd rather not type 40 commands by hand, there's a script for that.
After the [Prerequisites](#prerequisites) below:

```bash
git clone https://github.com/Abishek-Pechiappan/libfprint-elan-04f3-0c4b-tod ~/elan-fingerprint-fix
cd ~/elan-fingerprint-fix
./scripts/install.sh
```

It checks your device ID, builds and installs `libfprint-tod` (patch + LTO
fix already applied) and the proprietary ELAN driver, reloads udev, restarts
`fprintd`, and offers to enroll a finger right then and there.

It will **not** touch `/etc/pam.d/system-auth` or your Hyprland config —
those are personal/auth files, so at the end it just prints the commands for
Steps 9–10 and lets you decide.

If the script blows up (e.g. a meson option got renamed upstream), the manual
steps below are the fallback. Welcome to Linux.

---

## Prerequisites

On a fresh Arch install:

```bash
sudo pacman -S --needed base-devel git fprintd openssl-1.1
```

And an AUR helper, because we're about to need one (this guide uses `yay`):

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si
```

Finally, **clone this repo** so you have the patch file from Step 3:

```bash
git clone https://github.com/Abishek-Pechiappan/libfprint-elan-04f3-0c4b-tod ~/elan-fingerprint-fix
```

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

If your ID isn't `04f3:0c4b`, this guide may not apply — see "Background" for
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
"Background"). Steps 3–5 fix it.

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

---

## Background

### Why the stock `elan` driver fails

- `04f3:0c4b` is listed in `libfprint`'s **`elan`** driver (`elan.h`,
  `ELAN_ALL_DEV`), which speaks the *old swipe-sensor* protocol.
- It is **not** listed in the **`elanmoc`** driver (match-on-chip / press
  sensors) — not even in the experimental `elanmoc2` AUR forks
  (`libfprint-elanmoc2-git`, `-working`, etc.), which only add `0c4c`, `0c00`,
  `0c90`.
- End result: the `elan` driver claims the device, speaks the wrong protocol
  to it, and enrollment dies with `enroll-disconnected` / "the driver
  encountered a protocol error with the device" (visible in `journalctl -u
  fprintd`). Two strangers, no shared language.

There's a proprietary driver from Lenovo (originally shipped for the E14 Gen 4
on Ubuntu), packaged as the AUR `libfprint-2-tod1-elan`, whose udev rule
explicitly matches `04f3:0c4b` and forces libfprint to load it via the
`LIBFPRINT_DRIVER` env var — bypassing the lying `elan` driver entirely.

If your device ID **is** in the `elanmoc` driver's `id_table`
(`libfprint/drivers/elanmoc/elanmoc.c`), plain `libfprint`/`fprintd` from the
official repos should "just work" and you can close this tab.

### Why fingerprint login (SDDM/sudo/hyprlock) times out even after Step 6

Because `libfprint-2-tod1-elan`'s udev rule ships fully commented out (see
Step 7), the `LIBFPRINT_DRIVER=Elan Fingerprint Sensor` hint that's the entire
point of this package never gets applied to the device. Manual
`fprintd-list`/`fprintd-enroll`/`fprintd-verify` right after install can look
fine because they're mostly reading stored print data, not doing live hardware
I/O. But every PAM-driven verify (SDDM greeter, `sudo`, `hyprlock`) hangs for
the full ~30s timeout and falls back to your password, with `journalctl -u
fprintd` showing repeated `g_usb_device_bulk_transfer_finish failed: transfer
timed out` — the broken `elan` driver got probed for the actual scan instead
of the TOD one. Step 7 has the override rule that fixes this.

### Why `libfprint-tod-git` fails to build

`libfprint-2-tod1-elan` depends on `libfprint-tod` (a build of `libfprint`
with the TOD shim enabled, `provides=libfprint`, `conflicts=libfprint`). The
AUR package `libfprint-tod-git` (source: `3v1n0/libfprint#tod` branch,
currently `v1.95.1+tod1`) fails to build on current Arch with the linker error
from Step 2.

**Root cause**: `libfprint/libfprint/tod/tod-symbols.h` uses inline
`__asm__(".symver ...")` directives to assign default symbol versions to
functions like `fpi_ssm_new_full`, `fpi_ssm_jump_to_state_delayed`,
`fpi_ssm_mark_completed_delayed`, and `fpi_ssm_next_state_delayed` — all
versioned as `..._1.92`.

But `libfprint/libfprint/tod/libfprint-tod.ver.in` **also lists these same
symbol names as plain (unversioned) globals in the base version node**
(`LIBFPRINT_TOD_x.0.0`), which is inherited by the `_1.92` node. Two
conflicting version assignments for the same symbol — modern `ld` looks at
this, shrugs, and refuses to link.

Separately, with Arch's default `-flto=auto`, the `.symver` directives in
`tod-wrappers.c` end up in GCC's "slim LTO" objects with no real ELF symbol
table, which *also* breaks the version script. So LTO needs to go too (Step
4) — two unrelated bugs conspiring against you at once. Classic.

The patch in [`patches/0001-fix-duplicate-versioned-symbols-in-tod-version-script.patch`](patches/0001-fix-duplicate-versioned-symbols-in-tod-version-script.patch)
removes the duplicate plain symbol names from the base version node — they
remain correctly versioned via the `_1_90`-suffixed wrapper symbols and the
`_1.92` node, so nothing is actually lost.

---

## Caveats / maintenance

- `libfprint-tod-git` **conflicts with and replaces** the official
  `libfprint`. Any future `pacman -Syu` could decide it wants the official
  `libfprint` back (e.g. if `fprintd` starts requiring a newer `libfprint-2.so`
  soname than our `provides=libfprint-2.so=2-64` covers) — pacman would offer
  to remove `libfprint-tod-git`, and your fingerprint reader would quietly go
  back to lying to you.

  To stop this, add to the `[options]` section of `/etc/pacman.conf`:
  ```
  IgnorePkg = libfprint libfprint-tod-git libfprint-2-tod1-elan
  ```
  (`IgnorePkg` only works inside `[options]` — don't bury it in a repo
  section like `[core]` or a third-party repo block, pacman will just ignore
  your `IgnorePkg` instead, which is somehow funnier and worse.)

  With these ignored, `pacman -Syu` leaves them alone forever. If you ever
  *do* want to update `fprintd` or friends, temporarily remove the relevant
  entry, update, and check the fingerprint reader still works — you may need
  to rebuild `libfprint-tod-git` against the new version.

- `libfprint-2-tod1-elan` is a **closed-source binary blob**, sourced from
  Lenovo's official Ubuntu driver download and redistributed via
  [TonyHoyle/libfprint-2-tod1-elan](https://github.com/TonyHoyle/libfprint-2-tod1-elan).
  It's convenient, it's also a black box — review it before trusting it on a
  security-sensitive machine.

- If `pam_faillock` locks you out and "wrong password" appears even with the
  *correct* password (e.g. after a few failed `sudo`/polkit prompts while you
  were figuring all this out), reset it with:
  ```bash
  sudo faillock --user $USER --reset
  ```

---

## Acknowledgements

This repo doesn't invent anything new — it just glues together (and unbreaks)
the work of people who did the actual hard part:

- [3v1n0](https://gitlab.freedesktop.org/3v1n0/libfprint) for the
  `libfprint-tod` branch and the whole TOD shim architecture.
- [TonyHoyle](https://github.com/TonyHoyle/libfprint-2-tod1-elan) for digging
  the proprietary ELAN driver out of Lenovo's Ubuntu packages and making it
  installable elsewhere.
- Lenovo, technically, for writing a driver that works — just only for the
  one distro they tested on.

---

## Got this working (or not)?

This was tested on one specific laptop, so if you've got the same `04f3:0c4b`
sensor on different hardware, an issue or PR saying "yep, worked for me too"
(or "nope, here's what broke") is genuinely useful — it's the only way this
README gets better instead of slowly fossilizing into a historical document.
