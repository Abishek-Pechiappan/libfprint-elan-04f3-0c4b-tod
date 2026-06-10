#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/../patches/0001-fix-duplicate-versioned-symbols-in-tod-version-script.patch"

if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: patch file not found at $PATCH_FILE"
    exit 1
fi

WORKDIR="$(mktemp -d /tmp/libfprint-tod-build.XXXXXX)"
echo "==> Building libfprint-tod in $WORKDIR"

git clone --depth 1 -b tod https://gitlab.freedesktop.org/3v1n0/libfprint.git "$WORKDIR/src"
cd "$WORKDIR/src"

echo "==> Applying patch..."
git apply "$PATCH_FILE"

# Strip -flto=auto from any inherited build flags so it isn't reintroduced
export CFLAGS="${CFLAGS//-flto=auto/}"
export CXXFLAGS="${CXXFLAGS//-flto=auto/}"
export LDFLAGS="${LDFLAGS//-flto=auto/}"

echo "==> Configuring build (LTO disabled, TOD enabled)..."
if ! meson setup build \
    --prefix=/usr --sysconfdir=/etc --localstatedir=/var --buildtype=plain \
    -Db_lto=false \
    -Dtod=enabled \
    -Ddoc=disabled \
    -Dintrospection=disabled \
    -Dx11_examples=disabled \
    -Dgtk_examples=disabled \
    -Dvapi=disabled \
    -Dtests=disabled; then
    echo
    echo "ERROR: meson setup failed - one of the -D options above is likely"
    echo "unrecognized on this branch. Fall back to the manual yay-based"
    echo "Steps 2-5 in the main README, which don't hardcode meson options."
    exit 1
fi

echo "==> Building (this can take a while)..."
ninja -C build

PKGDIR="$WORKDIR/pkg"
echo "==> Installing build output to $PKGDIR ..."
meson install -C build --destdir "$PKGDIR"

PKGVER="1.95.1+tod1-1"
PKGFILE="libfprint-tod-git-${PKGVER}-x86_64.pkg.tar.zst"

cd "$PKGDIR"
cat > .PKGINFO <<EOF
pkgname = libfprint-tod-git
pkgbase = libfprint-tod-git
pkgver = ${PKGVER}
pkgdesc = Library for fingerprint readers - TOD version (LTO disabled, locally built)
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

echo "==> Packaging..."
fakeroot tar --zstd -cf "$WORKDIR/$PKGFILE" .PKGINFO usr

echo "==> Installing package (pacman may ask to remove the official libfprint - say yes)..."
sudo pacman -U "$WORKDIR/$PKGFILE"

echo "==> libfprint-tod build complete. Artifacts left in $WORKDIR"
echo "    (safe to 'rm -rf $WORKDIR' once everything works)"
