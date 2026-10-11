#!/usr/bin/env bash
# Fetch separately; do not bundle these tools into GPL compiler releases.
set -euo pipefail
out="$1"
mkdir -p "$out"
archive="$out/ow-snapshot.tar.xz"
curl --fail --location --retry 3 --output "$archive" \
  https://github.com/open-watcom/open-watcom-v2/releases/download/2026-10-01-Build/ow-snapshot.tar.xz
printf '%s  %s\n' e6aa1b1e40ac8bbf97658d2c70fff8a4242d6ca4a1c60806f2baa5317083d4fe "$archive" | sha256sum --check
tar -xJf "$archive" -C "$out" ./binl64/wlib ./binl64/wlink ./binl64/wlink.lnk
chmod +x "$out/binl64/wlib" "$out/binl64/wlink"
ln -s "$(command -v nasm)" "$out/binl64/nasm"
