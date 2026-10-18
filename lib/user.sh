# shellcheck shell=bash
# Per-user configuration: config layering, Hyprland stub, wallpapers, GTK/Qt/KDE settings.

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

# hyprqt6engine_conf HOME -> ~/.config/hypr/hyprqt6engine.conf: Qt and KDE apps in Hyprland use Noctalia's KDE color
# scheme (written by its kcolorscheme template), Breeze, Papirus and the desktop's fonts. Double-click opens files,
# like in GTK apps.
hyprqt6engine_conf() {
  cat <<EOF
theme {
    color_scheme = $1/.local/share/color-schemes/noctalia.colors
    icon_theme = Papirus-Dark
    style = Breeze
    font = Noto Sans
    font_size = 11
    font_fixed = JetBrains Mono
    font_fixed_size = 11
}

misc {
    single_click_activate = 0
}
EOF
}

# kde_settings CURSOR SIZE -> tab-separated "FILE GROUP KEY VALUE" lines for kwriteconfig6: the same look in KDE apps
# and in the Plasma fallback. ColorScheme is "noctalia" in lower case, the name Noctalia's template writes; a differently
# spelled copy would stop following theme changes.
kde_settings() {
  printf '%s\t%s\t%s\t%s\n' \
    kdeglobals General ColorScheme noctalia \
    kdeglobals General font "Noto Sans,11" \
    kdeglobals General fixed "JetBrains Mono,11" \
    kdeglobals Icons Theme Papirus-Dark \
    kdeglobals KDE widgetStyle Breeze \
    kdeglobals KDE SingleClick false \
    kcminputrc Mouse cursorTheme "$1" \
    kcminputrc Mouse cursorSize "$2" \
    kwalletrc Wallet Enabled false \
    kwalletrc Wallet "First Use" false
}

# uwsm_env_value ENV_FILE NAME DEFAULT -> the value ENV_FILE exports for NAME, DEFAULT when it has none.
uwsm_env_value() {
  local value
  value=$(sed -n "s/^export $2=//p" "$1" 2>/dev/null | tail -1)
  echo "${value:-$3}"
}

# Applied once, like set_desktop_settings: later changes in Plasma's System Settings stay. KWallet stays off, so
# gnome-keyring is the only keyring in both sessions. The cursor is the one the Hyprland session uses.
set_kde_settings() {
  local marker="$STATE_DIR/kde-settings-applied" env="$HOME/.config/uwsm/env" file group key value
  [[ -f "$marker" ]] && return 0
  have kwriteconfig6 || { warn "kwriteconfig6 is missing, so KDE apps keep their default look."; return 0; }
  while IFS=$'\t' read -r file group key value; do
    kwriteconfig6 --file "$file" --group "$group" --key "$key" "$value"
  done < <(kde_settings "$(uwsm_env_value "$env" XCURSOR_THEME Classic-pointer)" "$(uwsm_env_value "$env" XCURSOR_SIZE 32)")
  mkdir -p "$STATE_DIR"
  : >"$marker"
}

# Old default app -> KDE app, for migrate_kde_apps.
MIME_MIGRATION='thunar.desktop org.kde.dolphin.desktop
org.gnome.Papers.desktop okularApplication_pdf.desktop
com.interversehq.qView.desktop org.kde.gwenview.desktop
org.gnome.TextEditor.desktop org.kde.kate.desktop
org.gnome.FileRoller.desktop org.kde.ark.desktop'

# migrate_kde_apps CONFIG_DIR: once, moves an install from before the KDE apps over to them. Only the lines that
# changed are rewritten, so everything else you changed in these files stays.
migrate_kde_apps() {
  local marker="$STATE_DIR/kde-apps-migrated" from to portals="$1/xdg-desktop-portal/hyprland-portals.conf"
  [[ -f "$marker" ]] && return 0
  if [[ -f "$1/mimeapps.list" ]]; then
    while read -r from to; do
      sed -i "s/=${from//./\\.}\$/=$to/" "$1/mimeapps.list"
    done <<<"$MIME_MIGRATION"
  fi
  if [[ -f "$1/uwsm/env" ]]; then
    sed -i 's/^export QT_QPA_PLATFORMTHEME=qt6ct$/export QT_QPA_PLATFORMTHEME=hyprqt6engine/' "$1/uwsm/env"
    grep -q '^export XDG_MENU_PREFIX=' "$1/uwsm/env" || echo 'export XDG_MENU_PREFIX=plasma-' >>"$1/uwsm/env"
  fi
  if [[ -f "$portals" ]] && ! grep -q '^org.freedesktop.impl.portal.FileChooser=' "$portals"; then
    echo 'org.freedesktop.impl.portal.FileChooser=kde' >>"$portals"
  fi
  mkdir -p "$STATE_DIR"
  : >"$marker"
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
    gsettings set org.gnome.desktop.interface font-name "Noto Sans 11"
    gsettings set org.gnome.desktop.interface document-font-name "Noto Sans 11"
    gsettings set org.gnome.desktop.interface monospace-font-name "JetBrains Mono 11"
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
  migrate_kde_apps "$HOME/.config"
  for item in ghostty/config kitty/kitty.conf uwsm/env gtk-3.0/settings.ini gtk-4.0/settings.ini mimeapps.list \
    xdg-desktop-portal/hyprland-portals.conf xdg-desktop-portal/kde-portals.conf; do
    copy_once "$REPO_DIR/config/$item" "$HOME/.config/$item"
  done
  write_once "$HOME/.config/hypr/hyprqt6engine.conf" "$(hyprqt6engine_conf "$HOME")"
  write_once "$HOME/.config/hypr/hyprland.lua" "$(hypr_stub "$REPO_DIR")"
  # Noctalia's btop template only switches the theme in an existing btop.conf; btop fills in the rest itself.
  write_once "$HOME/.config/btop/btop.conf" 'color_theme = "noctalia"'
  download_wallpapers "$list" "$WALL_DIR"
  noctalia_local_toml "$(default_wallpaper "$list" "$WALL_DIR")" "$WALL_DIR" >"$HOME/.config/noctalia/10-fedora-hyprland-local.toml"
  set_desktop_settings
  set_kde_settings
  # Dolphin's "Open with" list and the KDE apps' file associations come from this cache.
  XDG_MENU_PREFIX=plasma- kbuildsycoca6 >/dev/null 2>&1 || warn "kbuildsycoca6 failed, so Dolphin's \"Open with\" may stay empty until you log in again."
  # Native host for the Pywalfox extension, so Firefox follows Noctalia's colors.
  noctalia firefox-theme install >/dev/null || warn "Could not set up Firefox theming (noctalia firefox-theme install)."
  # Noctalia writes to ~/.mozilla; Firefox 147+ reads ~/.config/mozilla on new installs.
  mkdir -p "$HOME/.config/mozilla/native-messaging-hosts"
  ln -sfn "$HOME/.mozilla/native-messaging-hosts/pywalfox.json" "$HOME/.config/mozilla/native-messaging-hosts/pywalfox.json"
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$REPO_DIR/bin/update" "$HOME/.local/bin/update"
}
