# shellcheck shell=bash
# Per-user configuration: config layering, Hyprland stub, wallpapers, GTK/Qt settings.

WALL_DIR="$HOME/Pictures/Wallpapers"
# hypr_stub REPO -> ~/.config/hypr/hyprland.lua (written once, then it's yours).
hypr_stub() {
  cat <<EOF
-- Your Hyprland config. fedora-hyprland created it once and never overwrites it.
-- The defaults live in $1/config/hypr and update with the \`update\` command.
require("$1/config/hypr/main.lua")("$1")

-- Your own changes go below this line.
EOF
}

# noctalia_local_toml WALLPAPER DIR -> per-user values Noctalia needs as absolute paths.
# The picker folder is pinned because XDG's Pictures folder is localized (e.g. ~/Bilder on a German system).
noctalia_local_toml() {
  cat <<EOF
# Written by fedora-hyprland on every install.sh run. The Settings GUI overrides it.
[wallpaper]
directory = "$2"

[wallpaper.default]
path = "$1"
EOF
}

# qt6ct_conf HOME -> Qt apps use Noctalia's colors and Papirus icons.
qt6ct_conf() {
  cat <<EOF
[Appearance]
color_scheme_path=$1/.config/qt6ct/colors/noctalia.conf
custom_palette=true
icon_theme=Papirus-Dark
style=Fusion
EOF
}

wallpaper_urls() { grep -vE '^[[:space:]]*(#|$)' "$1"; }
default_wallpaper() { echo "$2/$(basename "$(wallpaper_urls "$1" | head -1)")"; }

# download_wallpapers LIST DIR: fetch missing wallpapers; a failed download warns and continues.
download_wallpapers() {
  local url file
  mkdir -p "$2"
  while read -r url; do
    file="$2/$(basename "$url")"
    [[ -f "$file" ]] && continue
    if curl -fsSL --retry 2 -o "$file.part" "$url"; then
      mv "$file.part" "$file"
    else
      rm -f "$file.part"
      warn "Could not download wallpaper $url"
    fi
  done < <(wallpaper_urls "$1")
}

# Applied once: later runs (every `update`) keep what the user changed in nwg-look or Noctalia.
set_desktop_settings() {
  local marker="$STATE_DIR/desktop-settings-applied" settings='
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
    gsettings set org.gnome.desktop.interface cursor-theme Classic-pointer
    gsettings set org.gnome.desktop.interface cursor-size 32'
  [[ -f "$marker" ]] && return 0
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    sh -c "$settings"
  else
    dbus-run-session -- sh -c "$settings" # from a TTY there is no session bus yet
  fi
  mkdir -p "$STATE_DIR"
  : >"$marker"
}

setup_user() {
  local item list="$REPO_DIR/config/wallpapers.txt"
  xdg-user-dirs-update
  mkdir -p "$HOME/.config/noctalia"
  ln -sfn "$REPO_DIR/config/noctalia/00-fedora-hyprland.toml" "$HOME/.config/noctalia/00-fedora-hyprland.toml"
  for item in ghostty/config kitty/kitty.conf uwsm/env gtk-3.0/settings.ini gtk-4.0/settings.ini mimeapps.list \
    xdg-desktop-portal/hyprland-portals.conf; do
    copy_once "$REPO_DIR/config/$item" "$HOME/.config/$item"
  done
  write_once "$HOME/.config/qt6ct/qt6ct.conf" "$(qt6ct_conf "$HOME")"
  write_once "$HOME/.config/hypr/hyprland.lua" "$(hypr_stub "$REPO_DIR")"
  download_wallpapers "$list" "$WALL_DIR"
  noctalia_local_toml "$(default_wallpaper "$list" "$WALL_DIR")" "$WALL_DIR" >"$HOME/.config/noctalia/10-fedora-hyprland-local.toml"
  set_desktop_settings
  # Native host for the Pywalfox extension, so Firefox follows Noctalia's colors.
  noctalia firefox-theme install >/dev/null || warn "Could not set up Firefox theming (noctalia firefox-theme install)."
  # Noctalia writes to ~/.mozilla; Firefox 147+ reads ~/.config/mozilla on new installs.
  mkdir -p "$HOME/.config/mozilla/native-messaging-hosts"
  ln -sfn "$HOME/.mozilla/native-messaging-hosts/pywalfox.json" "$HOME/.config/mozilla/native-messaging-hosts/pywalfox.json"
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$REPO_DIR/bin/update" "$HOME/.local/bin/update"
}
