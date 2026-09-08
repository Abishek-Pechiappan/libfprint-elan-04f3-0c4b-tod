# Optional: the power-button indicator light

**This is purely cosmetic. Your fingerprint reader works fine without it.**
If enrolling and unlocking already work, you can close this file guilt-free.

## The situation

On some laptops the `04f3:0c4b` sensor is built into the power button, and
that button has a light in it. Under Windows it glows when the reader is
armed. Under Linux it stays dark — the kernel never registers it as an LED
device, so there's no `/sys/class/leds/` entry and nothing in userspace can
flip it the normal way.

The light isn't wired to the fingerprint protocol either; it's a separate
vendor command you have to send over USB yourself. The proprietary TOD driver
we install in the main guide doesn't bother.

## The community helper

[**DaDecky/elan-04f3-0c4b-fingerprint-led**](https://github.com/DaDecky/elan-04f3-0c4b-fingerprint-led)
is a small MIT-licensed C program (`libusb`) that sends the two vendor
commands the sensor understands:

| Command | Effect |
| --- | --- |
| `40 31` | indicator on (green on the Legion S7 15ACH6) |
| `00 0b` | indicator off |

It hooks into systemd as a drop-in on the `fprintd` service: the "on" command
runs as `ExecStartPre` (just before `fprintd` claims the sensor), the "off"
command as `ExecStopPost` (just after it lets go). Installation instructions
are in that repo — follow them there, not here, so you get whatever the
current version does.

## Why this is safe to try

- **It can't fight with the driver.** Only one program can hold the USB
  interface at a time, and the helper only runs in the gaps when `fprintd`
  isn't holding it. It never runs mid-scan.
- **It fails quietly.** If the LED command errors out, `fprintd` still starts
  and authentication is unaffected. Worst case: the light stays off, exactly
  like it does now.
- **No blobs.** It contains no Lenovo firmware or proprietary code — it just
  sends two bytes.

## Things to know before you install it

- **It is not per-scan feedback.** The light comes on when `fprintd` starts
  and goes off when it stops, so on a normal always-on system it's basically
  lit all the time. It tells you "the service is alive," not "swipe now."
- **The byte values are only confirmed on one machine** (Lenovo Legion S7
  15ACH6). Other laptops with the same `04f3:0c4b` sensor may wire the
  indicator differently, in which case the commands most likely do nothing.
- **It's a separate, third-party project**, not maintained here and not
  affiliated with this repo. Bug reports about the light belong in
  [its issue tracker](https://github.com/DaDecky/elan-04f3-0c4b-fingerprint-led/issues).
- It needs exclusive access to USB interface 0, and expects `libusb-1.0`,
  `pkgconf`, `fprintd` and systemd.

## Credit

Reverse-engineered and written by
[**@DaDecky**](https://github.com/DaDecky), who also confirmed the main
workaround in this repo works on the Lenovo Legion S7 15ACH6 — the first
report of it working on non-ThinkPad hardware.
