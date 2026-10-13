#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/user.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

full='   System Locale: LANG=de_DE.UTF-8
       VC Keymap: de-nodeadkeys
      X11 Layout: de
     X11 Variant: nodeadkeys'
console_only='   System Locale: LANG=de_DE.UTF-8
       VC Keymap: de-nodeadkeys
      X11 Layout: (unset)'
layout_only='      X11 Layout: us'
nothing='   System Locale: LANG=C.UTF-8
       VC Keymap: (unset)'
assert_eq "de|nodeadkeys" "$(kb_from_localectl "$full")"         "X11 layout and variant are used"
assert_eq "de|nodeadkeys" "$(kb_from_localectl "$console_only")" "console keymap is used when X11 is unset"
assert_eq "us|"           "$(kb_from_localectl "$layout_only")"  "layout without variant"
assert_eq "us|"           "$(kb_from_localectl "$nothing")"      "falls back to us"
KBD_MODEL_MAP=tests/fixtures/kbd-model-map
assert_eq "de|nodeadkeys" "$(kb_from_localectl "       VC Keymap: de-latin1-nodeadkeys")" "console keymap de-latin1-nodeadkeys maps to de/nodeadkeys"
assert_eq "de|"           "$(kb_from_localectl "       VC Keymap: de-latin1")"            "console keymap de-latin1 maps to de"
assert_eq "gb|"           "$(kb_from_localectl "       VC Keymap: uk")"                   "console keymap uk maps to gb"
assert_eq "us|intl"       "$(kb_from_localectl "       VC Keymap: us-acentos")"           "console keymap us-acentos maps to us/intl"
assert_eq "de|nodeadkeys" "$(kb_from_localectl "$console_only")"                          "keymaps missing from the map still split on the dash"

stub=$(hypr_stub /home/u/.local/share/fedora-hyprland de nodeadkeys)
assert_true "stub loads the repo defaults" grep -qF 'require("/home/u/.local/share/fedora-hyprland/config/hypr/main.lua")("/home/u/.local/share/fedora-hyprland")' <<<"$stub"
assert_true "stub sets the keyboard layout" grep -qF 'kb_layout = "de", kb_variant = "nodeadkeys"' <<<"$stub"
assert_false "GPU settings no longer live in the Hyprland stub" grep -qF 'gpu' <<<"$stub"

printf '# comment\n\nhttps://example.org/a/one.jpg\nhttps://example.org/b/two.png\n' >"$tmp/list.txt"
assert_eq $'https://example.org/a/one.jpg\nhttps://example.org/b/two.png' "$(wallpaper_urls "$tmp/list.txt")" "comments and blank lines are skipped"
assert_eq "$tmp/walls/one.jpg" "$(default_wallpaper "$tmp/list.txt" "$tmp/walls")" "first entry is the default"

curl_calls=0
curl() { # fake: -o FILE URL; fails for two.png
  curl_calls=$((curl_calls + 1))
  local out url
  while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
  [[ "$url" == *two.png ]] && return 22
  echo data >"$out"
}
download_wallpapers "$tmp/list.txt" "$tmp/walls" 2>/dev/null
assert_true  "a working URL is downloaded"         test -f "$tmp/walls/one.jpg"
assert_false "a failing URL leaves no file"        test -e "$tmp/walls/two.png"
assert_false "a failing URL leaves no .part file"  test -e "$tmp/walls/two.png.part"
curl_calls=0
download_wallpapers "$tmp/list.txt" "$tmp/walls" 2>/dev/null
assert_eq "1" "$curl_calls" "re-run only retries what is missing"

local_toml=$(noctalia_local_toml /w/one.jpg /w)
assert_true "local toml sets the default wallpaper" grep -qF 'path = "/w/one.jpg"' <<<"$local_toml"
assert_true "wallpaper picker browses the download folder (not ~/Bilder on a German system)" grep -qF 'directory = "/w"' <<<"$local_toml"

# Desktop settings are applied once: later runs (every `update`) keep what the user changed.
mkdir -p "$tmp/fakebin"; log="$tmp/gs.log"; : >"$log"
printf '#!/bin/sh\necho dbus-run-session >>"%s"\nshift\nexec "$@"\n' "$log" >"$tmp/fakebin/dbus-run-session"
printf '#!/bin/sh\necho "gsettings $*" >>"%s"\n' "$log" >"$tmp/fakebin/gsettings"
chmod +x "$tmp/fakebin/dbus-run-session" "$tmp/fakebin/gsettings"
STATE_DIR="$tmp/state"
( unset DBUS_SESSION_BUS_ADDRESS; PATH="$tmp/fakebin:$PATH" set_desktop_settings )
assert_true "first run applies the icon theme"  grep -qF 'gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark' "$log"
assert_true "outside a session it starts its own bus" grep -qx 'dbus-run-session' "$log"
: >"$log"
( PATH="$tmp/fakebin:$PATH" set_desktop_settings )
assert_eq "" "$(cat "$log")" "second run leaves the user's settings alone"
rm -f "$STATE_DIR"/desktop-settings-applied; : >"$log"
( DBUS_SESSION_BUS_ADDRESS=unix:path=/fake PATH="$tmp/fakebin:$PATH" set_desktop_settings )
assert_false "inside a running session it uses that session's bus" grep -qx 'dbus-run-session' "$log"
assert_true "qt6ct uses Noctalia's colors" grep -qF 'color_scheme_path=/home/u/.config/qt6ct/colors/noctalia.conf' <<<"$(qt6ct_conf /home/u)"
finish
