# shellcheck shell=bash
# Apps that don't come from dnf or Flathub.

ARTCRAFT_REPO="storytold/craft-launcher" # official; github.com/craft-launcher/craft-launcher is a lookalike
ARTCRAFT_APPIMAGE="$HOME/Applications/ArtCraft-Launcher.AppImage"
TOOLBOX_DIR="$HOME/.local/share/JetBrains/Toolbox"
NERD_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd" # Fedora packages no Nerd Fonts

# sha256_ok FILE SUMS_FILE -> 0 when FILE's sha256 is listed for its basename in SUMS_FILE.
sha256_ok() {
  local want got
  want=$(awk -v n="$(basename "$1")" '$2 == n || $2 == "*"n {print $1}' "$2")
  [[ -n "$want" ]] || return 1
  got=$(sha256sum "$1" | cut -d' ' -f1)
  [[ "$got" == "$want" ]]
}

# write_desktop_entry ID NAME EXEC ICON CATEGORIES -> ~/.local/share/applications/ID.desktop
write_desktop_entry() {
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
Categories=$5
Terminal=false
EOF
}

install_jetbrains_toolbox() {
  local url tmp
  [[ -x "$TOOLBOX_DIR/bin/jetbrains-toolbox" ]] && return 0
  url=$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' |
    jq -r '.TBA[0].downloads.linux.link')
  tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1
  # Toolbox 2.x lives in ~/.local/share/JetBrains/Toolbox/bin and updates itself there.
  mkdir -p "$TOOLBOX_DIR"
  cp -r "$tmp"/. "$TOOLBOX_DIR"/
  rm -rf "$tmp"
  write_desktop_entry jetbrains-toolbox "JetBrains Toolbox" "$TOOLBOX_DIR/bin/jetbrains-toolbox" \
    "$TOOLBOX_DIR/bin/toolbox-tray-color.png" "Development;"
}

install_claude_code() {
  have claude && return 0
  [[ -x "$HOME/.local/bin/claude" ]] && return 0
  curl -fsSL https://claude.ai/install.sh | bash
}

# install_nerd_font: JetBrains Mono Nerd Font (prompt and eza/yazi icons) from the official release, checksum-verified.
install_nerd_font() {
  local json font_url sums_url tmp
  [[ -d "$NERD_FONT_DIR" ]] && return 0
  json=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest)
  font_url=$(jq -r '.assets[] | select(.name == "JetBrainsMono.tar.xz") | .browser_download_url' <<<"$json")
  sums_url=$(jq -r '.assets[] | select(.name == "SHA-256.txt") | .browser_download_url' <<<"$json")
  if [[ -z "$font_url" || -z "$sums_url" ]]; then warn "Nerd Fonts release has no JetBrainsMono archive, skipped."; return 0; fi
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/JetBrainsMono.tar.xz" "$font_url"
  curl -fsSL -o "$tmp/SHA-256.txt" "$sums_url"
  if ! sha256_ok "$tmp/JetBrainsMono.tar.xz" "$tmp/SHA-256.txt"; then
    warn "Nerd Font download failed its checksum check, so it was not installed."
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p "$NERD_FONT_DIR"
  tar -xJf "$tmp/JetBrainsMono.tar.xz" -C "$NERD_FONT_DIR" --wildcards '*.ttf'
  rm -rf "$tmp"
  fc-cache -f "$NERD_FONT_DIR" >/dev/null
}

install_apps() {
  install_jetbrains_toolbox
  install_claude_code
  install_nerd_font
}

# install_artcraft: official AppImage, checksum-verified, never run as root.
install_artcraft() {
  local json app_url sums_url tmp name
  json=$(curl -fsSL "https://api.github.com/repos/$ARTCRAFT_REPO/releases/latest")
  app_url=$(jq -r '.assets[] | select(.name | test("linux-x86_64\\.AppImage$")) | .browser_download_url' <<<"$json")
  sums_url=$(jq -r '.assets[] | select(.name == "SHA256SUMS.txt") | .browser_download_url' <<<"$json")
  if [[ -z "$app_url" || -z "$sums_url" ]]; then warn "ArtCraft release has no Linux AppImage or checksums, skipped."; return 0; fi
  tmp=$(mktemp -d)
  name=$(basename "$app_url")
  curl -fsSL -o "$tmp/$name" "$app_url"
  curl -fsSL -o "$tmp/SHA256SUMS.txt" "$sums_url"
  if ! sha256_ok "$tmp/$name" "$tmp/SHA256SUMS.txt"; then
    warn "ArtCraft download failed its checksum check, so it was not installed."
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$ARTCRAFT_APPIMAGE")"
  install -m 755 "$tmp/$name" "$ARTCRAFT_APPIMAGE"
  rm -rf "$tmp"
  write_desktop_entry artcraft-launcher "ArtCraft Launcher" "$ARTCRAFT_APPIMAGE" applications-graphics "Graphics;"
}
