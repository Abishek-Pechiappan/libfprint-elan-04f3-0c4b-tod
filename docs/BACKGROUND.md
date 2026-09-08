# Background — why any of this is needed

Everything in this file is optional reading. It's here so the workaround isn't
a pile of magic commands you have to take on faith, and so that whoever fixes
this properly upstream has the details written down somewhere.

Install instructions live in the [README](../README.md) (quick) and
[MANUAL-INSTALL.md](MANUAL-INSTALL.md) (step by step).

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

The patch in [`patches/0001-fix-duplicate-versioned-symbols-in-tod-version-script.patch`](../patches/0001-fix-duplicate-versioned-symbols-in-tod-version-script.patch)
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
