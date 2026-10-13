#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/apps.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
file=tests/fixtures/sums/hello.AppImage
good=$(sha256sum "$file" | cut -d' ' -f1)
printf '%s  hello.AppImage\n%s  other.deb\n' "$good" "0000" >"$tmp/good.txt"
printf '%s  hello.AppImage\n' "deadbeef" >"$tmp/bad.txt"
printf '%s  other.deb\n' "$good" >"$tmp/absent.txt"
assert_true  "matching checksum is accepted"       sha256_ok "$file" "$tmp/good.txt"
assert_false "wrong checksum is rejected"          sha256_ok "$file" "$tmp/bad.txt"
assert_false "file missing from SHA256SUMS fails"  sha256_ok "$file" "$tmp/absent.txt"

HOME="$tmp" write_desktop_entry demo "Demo App" "/opt/demo --flag" demo-icon "Graphics;"
entry=$(cat "$tmp/.local/share/applications/demo.desktop")
assert_true "desktop entry has Exec" grep -qx 'Exec=/opt/demo --flag' <<<"$entry"
assert_true "desktop entry has Name" grep -qx 'Name=Demo App' <<<"$entry"
finish
