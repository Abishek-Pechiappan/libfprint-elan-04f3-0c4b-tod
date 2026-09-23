#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing prerequisites..."
sudo pacman -S --needed base-devel git fprintd openssl meson ninja glib2-devel
