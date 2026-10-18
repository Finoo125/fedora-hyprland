#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/user.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

stub=$(hypr_stub /home/u/.local/share/fedora-hyprland)
assert_true "stub loads the repo defaults" grep -qF 'require("/home/u/.local/share/fedora-hyprland/config/hypr/main.lua")("/home/u/.local/share/fedora-hyprland")' <<<"$stub"
assert_false "keyboard layout lives in the repo defaults, not the stub" grep -qF 'kb_layout' <<<"$stub"
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
assert_true "GTK apps use the Qt apps' font"   grep -qF 'gsettings set org.gnome.desktop.interface font-name Noto Sans 11' "$log"
assert_true "outside a session it starts its own bus" grep -qx 'dbus-run-session' "$log"
: >"$log"
( PATH="$tmp/fakebin:$PATH" set_desktop_settings )
assert_eq "" "$(cat "$log")" "second run leaves the user's settings alone"
rm -f "$STATE_DIR"/desktop-settings-applied; : >"$log"
( DBUS_SESSION_BUS_ADDRESS=unix:path=/fake PATH="$tmp/fakebin:$PATH" set_desktop_settings )
assert_false "inside a running session it uses that session's bus" grep -qx 'dbus-run-session' "$log"
qt=$(hyprqt6engine_conf /home/u)
assert_true "Qt and KDE apps use Noctalia's KDE color scheme" grep -qF 'color_scheme = /home/u/.local/share/color-schemes/noctalia.colors' <<<"$qt"
assert_true "Qt apps use Breeze" grep -qF 'style = Breeze' <<<"$qt"
assert_true "double-click opens files, like before" grep -qF 'single_click_activate = 0' <<<"$qt"
assert_true "the uwsm env picks hyprqt6engine" grep -qx 'export QT_QPA_PLATFORMTHEME=hyprqt6engine' config/uwsm/env
assert_true "the uwsm env sets Plasma's menu for Dolphin" grep -qx 'export XDG_MENU_PREFIX=plasma-' config/uwsm/env
assert_true "Noctalia writes the KDE color scheme" grep -qF '"kcolorscheme"' config/noctalia/00-fedora-hyprland.toml
assert_false "the plain qt template no longer competes with it" grep -qF '"qt"' config/noctalia/00-fedora-hyprland.toml

kde=$(kde_settings Windows-Cursors 24)
assert_true "KDE color scheme is the lower-case name Noctalia writes" grep -qxP 'kdeglobals\tGeneral\tColorScheme\tnoctalia' <<<"$kde"
assert_true "KDE cursor is the session's cursor" grep -qxP 'kcminputrc\tMouse\tcursorTheme\tWindows-Cursors' <<<"$kde"
assert_true "KWallet is off, gnome-keyring is the keyring" grep -qxP 'kwalletrc\tWallet\tEnabled\tfalse' <<<"$kde"
assert_eq "4" "$(awk -F'\t' '{print NF}' <<<"$kde" | sort -u)" "every KDE setting has file, group, key and value"
printf 'export XCURSOR_THEME=Windows-Cursors\nexport XCURSOR_SIZE=24\n' >"$tmp/env"
assert_eq "Windows-Cursors" "$(uwsm_env_value "$tmp/env" XCURSOR_THEME Classic-pointer)" "cursor comes from the uwsm env"
assert_eq "Classic-pointer" "$(uwsm_env_value "$tmp/missing" XCURSOR_THEME Classic-pointer)" "default cursor without a uwsm env"

# An install from before the KDE apps: its own files are patched line by line, everything else stays.
old="$tmp/old/.config"; mkdir -p "$old/uwsm" "$old/xdg-desktop-portal"
printf '[Default Applications]\ninode/directory=thunar.desktop\napplication/pdf=org.gnome.Papers.desktop\nx-scheme-handler/jetbrains=jetbrainsd.desktop\n' >"$old/mimeapps.list"
printf 'export XCURSOR_THEME=Windows-Cursors\nexport QT_QPA_PLATFORMTHEME=qt6ct\n' >"$old/uwsm/env"
printf '[preferred]\ndefault=hyprland;gtk\n' >"$old/xdg-desktop-portal/hyprland-portals.conf"
STATE_DIR="$tmp/state-migrate"
migrate_kde_apps "$old"
assert_true "folders open in Dolphin" grep -qx 'inode/directory=org.kde.dolphin.desktop' "$old/mimeapps.list"
assert_true "PDFs open in Okular" grep -qx 'application/pdf=okularApplication_pdf.desktop' "$old/mimeapps.list"
assert_true "your own handlers stay" grep -qx 'x-scheme-handler/jetbrains=jetbrainsd.desktop' "$old/mimeapps.list"
assert_true "your cursor stays" grep -qx 'export XCURSOR_THEME=Windows-Cursors' "$old/uwsm/env"
assert_true "Qt switches to hyprqt6engine" grep -qx 'export QT_QPA_PLATFORMTHEME=hyprqt6engine' "$old/uwsm/env"
assert_true "Dolphin finds the app menu" grep -qx 'export XDG_MENU_PREFIX=plasma-' "$old/uwsm/env"
assert_true "file dialogs become KDE's" grep -qx 'org.freedesktop.impl.portal.FileChooser=kde' "$old/xdg-desktop-portal/hyprland-portals.conf"
printf 'inode/directory=thunar.desktop\n' >"$old/mimeapps.list"
migrate_kde_apps "$old"
assert_true "the migration runs only once, so a later choice of Thunar stays" grep -qx 'inode/directory=thunar.desktop' "$old/mimeapps.list"
assert_eq "" "$(grep -E 'thunar|gnome|qView' config/mimeapps.list)" "new installs get only KDE apps as defaults"
finish
