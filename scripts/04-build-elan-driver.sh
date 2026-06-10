#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(mktemp -d /tmp/libfprint-elan-tod-build.XXXXXX)"
echo "==> Building libfprint-2-tod1-elan in $WORKDIR"

git clone --depth 1 https://github.com/TonyHoyle/libfprint-2-tod1-elan "$WORKDIR/src"

PKGDIR="$WORKDIR/pkg"
mkdir -p "$PKGDIR/usr/lib/libfprint-2/tod-1" "$PKGDIR/usr/lib/udev/rules.d"

cp "$WORKDIR/src/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod1-elan.so" \
   "$PKGDIR/usr/lib/libfprint-2/tod-1/"
cp "$WORKDIR/src/lib/udev/rules.d/60-libfprint-2-tod1-elan.rules" \
   "$PKGDIR/usr/lib/udev/rules.d/"

PKGVER="0.0.1-2"
PKGFILE="libfprint-2-tod1-elan-${PKGVER}-x86_64.pkg.tar.zst"

cd "$PKGDIR"
cat > .PKGINFO <<EOF
pkgname = libfprint-2-tod1-elan
pkgbase = libfprint-2-tod1-elan
pkgver = ${PKGVER}
pkgdesc = Proprietary driver for the Elan 04f3:0c4b fingerprint reader, from Lenovo E14 Gen 4 Ubuntu driver.
url = https://github.com/TonyHoyle/libfprint-2-tod1-elan
arch = x86_64
license = custom
group = fprint
depend = libfprint-tod
depend = libcrypto.so=1.1
EOF

echo "==> Packaging..."
fakeroot tar --zstd -cf "$WORKDIR/$PKGFILE" .PKGINFO usr

echo "==> Installing package..."
sudo pacman -U "$WORKDIR/$PKGFILE"

echo "==> libfprint-2-tod1-elan build complete. Artifacts left in $WORKDIR"
echo "    (safe to 'rm -rf $WORKDIR' once everything works)"
