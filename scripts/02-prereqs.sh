#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing prerequisites..."
sudo pacman -S --needed base-devel git fprintd openssl-1.1 meson ninja
