# Getting the ELAN 04f3:0c4b Fingerprint Reader Working (Arch Linux)

So you bought a laptop with a fingerprint reader, you're running Arch like a
responsible adult, and `fprintd-enroll` just... doesn't work. Cool. Cool cool
cool.

This repo makes the ELAN sensor with USB ID **`04f3:0c4b`** actually work —
enroll, `sudo`, login, and screen-lock unlock.

## Does this apply to me?

Run this:

```bash
lsusb | grep -i 04f3:0c4b
```

- **Something printed?** You're in the right place. Keep reading.
- **Nothing printed?** Wrong guide, sorry. Your sensor is a different model
  and needs a different fix.

## What's actually wrong (the 30-second version)

`libfprint` ships an open-source `elan` driver that *claims* to support
`04f3:0c4b`. It's lying. It speaks an older protocol than your sensor does, so
enrollment dies with `enroll-disconnected` and a "protocol error with the
device" in the logs.

Nobody has reverse-engineered the real protocol for `libfprint` yet. So the
workaround is to use **Lenovo's proprietary driver** instead, via a plugin
system called TOD. That driver needs a special build of `libfprint`, and *that*
build is currently broken on Arch. This repo unbreaks it.

If you want the gory details, they're in
[docs/BACKGROUND.md](docs/BACKGROUND.md).

---

## Install

**1. Get the prerequisites** (Arch, with an AUR helper — this guide uses `yay`):

```bash
sudo pacman -S --needed base-devel git fprintd openssl-1.1
```

**2. Clone and run the installer:**

```bash
git clone https://github.com/Abishek-Pechiappan/libfprint-elan-04f3-0c4b-tod ~/elan-fingerprint-fix
cd ~/elan-fingerprint-fix
./scripts/install.sh
```

The script checks your device, builds and installs the patched `libfprint-tod`
plus the proprietary ELAN driver, fixes the udev rule, restarts `fprintd`, and
offers to enroll a finger.

It deliberately **won't** touch your PAM config or your window manager setup —
those are your auth files. It prints the two commands for that at the end
instead (they're in the next section).

> Prefer to type all 40 commands yourself, or need to recover after the script
> dies? Full manual walkthrough:
> **[docs/MANUAL-INSTALL.md](docs/MANUAL-INSTALL.md)**

**3. Check it worked:**

```bash
fprintd-verify
```

Touch the sensor. If it says `verify-match`, the hard part is done.

---

## Use your finger instead of your password

**Polkit agent** — only needed on a bare window manager like Hyprland or
Sway. On GNOME/KDE, skip this; you already have one.

```bash
yay -S hyprpolkitagent
# then launch /usr/lib/hyprpolkitagent/hyprpolkitagent from your WM autostart
```

Without it, `fprintd-enroll` fails instantly with `PermissionDenied`.

**PAM integration** — this is what makes `sudo`, login and `hyprlock` accept a
fingerprint:

```bash
sudo sed -i '/^auth.*pam_faillock.so.*preauth/i auth       sufficient                  pam_fprintd.so' /etc/pam.d/system-auth
```

`sufficient` means a good scan lets you straight in, and a failed or ignored
scan just falls back to the password prompt as normal — it won't lock you out.

Test it:

```bash
sudo -k && sudo true    # touch the sensor when it asks
hyprlock                # Super+L, then touch the sensor
```

If `hyprlock` unlocks with your fingerprint, congratulations — you have
successfully turned a $5 sensor that the manufacturer half-implemented into a
working biometric lock through sheer spite.

---

## If something's broken

| Symptom | Fix |
| --- | --- |
| Fingerprint prompt appears in `sudo`/login/`hyprlock` but always times out (~30s) and falls back to the password | The udev override rule is missing or wasn't reloaded — **Step 7** in [docs/MANUAL-INSTALL.md](docs/MANUAL-INSTALL.md) |
| `fprintd-enroll` fails immediately with `PermissionDenied` | No polkit agent running — see the section above |
| `fprintd-list` says **ElanTech** Fingerprint Sensor | Wrong (open-source) driver is loaded. Correct output says **ELAN** Fingerprint Sensor, no "Tech" — again, Step 7 |
| Build fails with `no symbol version section for versioned symbol` | The known upstream bug this repo patches — run the installer, or Steps 3–5 manually |
| "Wrong password" even with the *correct* password | `pam_faillock` locked you out during all the fumbling: `sudo faillock --user $USER --reset` |

Still stuck? Logs are in `journalctl -u fprintd -f` — run that in one terminal
while you try to scan in another.

---

## Read more

- **[docs/MANUAL-INSTALL.md](docs/MANUAL-INSTALL.md)** — every command, step by
  step, with explanations.
- **[docs/BACKGROUND.md](docs/BACKGROUND.md)** — why the stock driver fails,
  why the build breaks, and **important maintenance notes** (this setup
  replaces the official `libfprint`, so you probably want the `IgnorePkg` tip
  in there before your next `pacman -Syu`).
- **[docs/LED-INDICATOR.md](docs/LED-INDICATOR.md)** — optional, cosmetic: get
  the power-button indicator light working, via a third-party helper.

## Heads up

`libfprint-2-tod1-elan` is a **closed-source binary blob** from Lenovo's Ubuntu
driver package. It works, but it's a black box — review it before trusting it
on a security-sensitive machine. Details and the other caveats are in
[docs/BACKGROUND.md](docs/BACKGROUND.md).

## Confirmed working on

| Laptop | Sensor | Notes |
| --- | --- | --- |
| Lenovo ThinkPad (Arch + Hyprland) | `04f3:0c4b` | Original testing machine, as of June 2026 |
| Lenovo Legion S7 15ACH6 | `04f3:0c4b` | Reported by [@DaDecky](https://github.com/DaDecky); indicator LED needs [the optional helper](docs/LED-INDICATOR.md) |

Tested against `libfprint-tod-git` v1.95.1+tod1 (`3v1n0/libfprint#tod` branch).
If `yay -S libfprint-2-tod1-elan` just works out of the box for you now, the
upstream bug has been fixed — congrats, close this tab and enjoy your
fingerprint reader.

## Acknowledgements

This repo doesn't invent anything new — it just glues together (and unbreaks)
the work of people who did the actual hard part:

- [3v1n0](https://gitlab.freedesktop.org/3v1n0/libfprint) for the
  `libfprint-tod` branch and the whole TOD shim architecture.
- [TonyHoyle](https://github.com/TonyHoyle/libfprint-2-tod1-elan) for digging
  the proprietary ELAN driver out of Lenovo's Ubuntu packages and making it
  installable elsewhere.
- [DaDecky](https://github.com/DaDecky/elan-04f3-0c4b-fingerprint-led) for
  working out the indicator-LED commands and confirming this workaround on
  Legion hardware.
- Lenovo, technically, for writing a driver that works — just only for the one
  distro they tested on.

## Got this working (or not)?

This was tested on a handful of laptops, so if you've got the same `04f3:0c4b`
sensor on different hardware, an issue or PR saying "yep, worked for me too"
(or "nope, here's what broke") is genuinely useful — it's the only way this
README gets better instead of slowly fossilizing into a historical document.
