# shellcheck shell=bash
# Package sources and package lists. Every function here is safe to run again.

COPR_REPO="lionheartp/Hyprland"
TERRA_ALLOW="noctalia-greeter*,ghostty*,signal-desktop*,heroic-games-launcher*,protonplus*,faugus-launcher*,mission-center*"
VSCODE_REPO='[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc'

DNF_BASE=(dnf5-plugins flatpak pciutils jq)
DNF_DESKTOP=(hyprland hyprland-guiutils uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk noctalia greetd noctalia-greeter
  pipewire pipewire-pulseaudio wireplumber bluez NetworkManager-wifi nm-connection-editor tuned-ppd upower
  gnome-keyring gnome-keyring-pam gcr dconf ddcutil bolt polkit qt5-qtwayland qt6-qtwayland hyprqt6engine plasma-breeze-qt6 nwg-look adw-gtk3-theme papirus-icon-theme
  xsettingsd google-noto-sans-fonts google-noto-color-emoji-fonts jetbrains-mono-fonts-all
  google-noto-sans-cjk-fonts liberation-fonts-all wl-clipboard grim slurp hyprpicker gpu-screen-recorder udiskie
  xdg-user-dirs xdg-utils xdg-terminal-exec libnotify playerctl brightnessctl)
# KDE apps: they read Noctalia's KDE color scheme (kdeglobals), so they match the desktop in Hyprland and in Plasma.
DNF_APPS=(ghostty kitty dolphin ark okular gwenview kate kcalc kde-partitionmanager plasma-discover plasma-discover-flatpak
  ffmpegthumbs kdegraphics-thumbnailers firefox mpv mpv-mpris kde-connect
  pavucontrol thunderbird telegram-desktop discord flatseal
  signal-desktop heroic-games-launcher protonplus faugus-launcher mission-center)
# Drives, network shares and devices in Dolphin: kio-extras (smb, nfs, sftp, mtp, afc for iPhones), kamera (cameras).
# kio-fuse gives smb://, mtp:// etc. a real path so non-KDE apps (mpv, ...) can open files there too.
# gvfs stays for the GTK apps (trash, recent files).
DNF_STORAGE=(kio-extras kio-fuse kamera gvfs
  udisks2 udisks2-btrfs ntfs-3g exfatprogs dosfstools udftools hfsplus-tools btrfs-progs xfsprogs
  cifs-utils nfs-utils samba-client fuse-sshfs libimobiledevice-utils ifuse unrar)
DNF_CLI=(git gh wget2-wget curl fastfetch btop bat eza fzf ripgrep fd-find zoxide unzip 7zip bash-completion plocate rsync ImageMagick)
DNF_MEDIA=(intel-media-driver libva-utils)
# AMD only: Fedora's mesa leaves out H.264/HEVC hardware decoding, RPM Fusion's build has it.
DNF_AMD=(mesa-va-drivers-freeworld)
DNF_GAMING=(steam gamemode mangohud gamescope lutris protontricks winetricks vulkan-tools)
DNF_SYSTEM=(fuse-libs cups cups-pk-helper cups-pdf hplip gutenprint-cups foomatic-db system-config-printer avahi nss-mdns
  NetworkManager-openvpn-gnome NetworkManager-openconnect-gnome wireguard-tools fprintd fprintd-pam
  snapper btrfs-assistant btrfsmaintenance smartmontools libdnf5-plugin-actions fwupd thermald intel-lpmd inotify-tools)
DNF_DEV=(gcc make uv python3 python3.12 python3.13 nodejs24 nodejs24-npm podman distrobox code
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
DNF_NVIDIA=(akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-power
  libva-nvidia-driver switcheroo-control)
DNF_SECUREBOOT=(kmodtool akmods mokutil openssl)
# Minimal KDE Plasma, a fallback session on the login screen for when Hyprland breaks. Installed without weak
# dependencies, so no Plasma Login Manager, KWallet or kde-gtk-config (which rewrites the GTK settings).
DNF_PLASMA=(plasma-workspace plasma-desktop kwin plasma-systemsettings kscreen plasma-nm plasma-pa powerdevil bluedevil
  polkit-kde xdg-desktop-portal-kde)
# Replaced by the KDE apps above; removed once when an older install is migrated (see remove_replaced_apps).
REPLACED_PACKAGES=(Thunar thunar-archive-plugin thunar-volman tumbler ffmpegthumbnailer file-roller qview papers
  gnome-text-editor gnome-calculator gnome-software gnome-software-fedora-langpacks gnome-disk-utility gparted xfce-polkit
  vlc qt6ct gvfs-fuse gvfs-smb gvfs-nfs gvfs-mtp gvfs-afc gvfs-gphoto2 gvfs-archive)
# Only apps without an RPM in Fedora, RPM Fusion or Terra; everything else comes from dnf.
FLATPAKS=(com.rtosta.zapzap com.bitwarden.desktop md.obsidian.Obsidian io.dbeaver.DBeaverCommunity
  org.localsend.localsend_app it.mijorus.gearlever org.gnome.World.PikaBackup)

# all_dnf_packages -> every dnf package the installer may install, one per line (CI checks they exist).
all_dnf_packages() {
  printf '%s\n' "${DNF_BASE[@]}" "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_STORAGE[@]}" "${DNF_CLI[@]}" "${DNF_MEDIA[@]}" \
    "${DNF_GAMING[@]}" "${DNF_SYSTEM[@]}" "${DNF_DEV[@]}" "${DNF_NVIDIA[@]}" "${DNF_SECUREBOOT[@]}" "${DNF_AMD[@]}" \
    "${DNF_PLASMA[@]}" ffmpeg
}

# main_dnf_packages -> the packages install_packages installs in one dnf transaction, one per line.
main_dnf_packages() {
  printf '%s\n' "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_STORAGE[@]}" "${DNF_CLI[@]}" "${DNF_SYSTEM[@]}" \
    "${DNF_GAMING[@]}" "${DNF_DEV[@]}"
}

# Other desktops' shells, sessions and login managers. A dependency that drags one in (as GParted once did
# with GNOME Shell) installs hundreds of MB the Hyprland setup never uses. Plasma comes only from DNF_PLASMA.
FOREIGN_DESKTOP=(gnome-shell gnome-session mutter gdm kwin plasma-workspace sddm plasma-login-manager cinnamon
  xfce4-session mate-session-manager lightdm)
# The Plasma fallback may bring KDE's own pieces, but never a second login manager or another desktop.
FOREIGN_TO_PLASMA=(gnome-shell gnome-session mutter gdm sddm plasma-login-manager cinnamon xfce4-session
  mate-session-manager lightdm)

# foreign_desktop_packages [NAME...]: stdin = `dnf install --assumeno` output -> the packages it would install
# that are in NAME... (default: FOREIGN_DESKTOP).
foreign_desktop_packages() {
  local -a names=("$@")
  ((${#names[@]})) || names=("${FOREIGN_DESKTOP[@]}")
  awk 'NF >= 5 {print $1}' | grep -xF -f <(printf '%s\n' "${names[@]}") || true
}

# removal_names: stdin = `dnf remove --assumeno` output -> the packages it would remove, one per line.
removal_names() {
  awk '/^Removing/ {on = 1; next} /^[A-Z]/ {on = 0} on && NF >= 5 {print $1}'
}

# has_amd_gpu LINES -> 0 when LINES (`lspci -d ::03xx`) contain an AMD/ATI GPU.
has_amd_gpu() { grep -qE '\b(AMD|ATI)\b' <<<"$1"; }

# terra_extra_repos: stdin = `dnf repo list --all` output -> Terra repo ids except the main "terra" repo.
terra_extra_repos() { awk '$1 ~ /^terra-/ {print $1}'; }

setup_repos() {
  local fedora repo
  fedora=$(rpm -E %fedora)
  sudo dnf install -y "${DNF_BASE[@]}"
  if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
    sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora}.noarch.rpm"
  fi
  sudo dnf copr enable -y "$COPR_REPO"
  if ! rpm -q terra-release >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # $releasever is expanded by dnf, not by the shell
    sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
  fi
  # Terra only provides the greeter, Ghostty and apps Fedora and RPM Fusion don't package;
  # nothing else from it may replace Fedora packages.
  sudo dnf config-manager setopt "terra.includepkgs=$TERRA_ALLOW"
  for repo in $(dnf repo list --all | terra_extra_repos); do
    sudo dnf config-manager setopt "$repo.enabled=0"
  done
  if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  write_root /etc/yum.repos.d/vscode.repo "$VSCODE_REPO"
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

install_packages() {
  local pkgs
  mapfile -t pkgs < <(main_dnf_packages)
  sudo dnf install -y "${pkgs[@]}"
  # RPM Fusion's full ffmpeg replaces Fedora's ffmpeg-free; the multimedia group adds the matching GStreamer plugins.
  sudo dnf install -y --allowerasing ffmpeg
  sudo dnf group install -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
  sudo dnf install -y "${DNF_MEDIA[@]}"
  if has_amd_gpu "$(lspci -d ::03xx)" && ! rpm -q "${DNF_AMD[@]}" >/dev/null 2>&1; then
    sudo dnf swap -y mesa-va-drivers "${DNF_AMD[@]}"
  fi
  # Minimal Install leaves out the firmware for Wi-Fi, Bluetooth and audio chips (e.g. Intel iwlwifi).
  sudo dnf group install -y hardware-support
  sudo dnf install -y --setopt=install_weak_deps=False "${DNF_PLASMA[@]}"
  remove_replaced_apps
}

# remove_replaced_apps: once per machine, removes the GTK apps an older install had where a KDE app took over.
# Skipped (with a warning) if dnf would also remove anything else, so nothing you added yourself disappears.
remove_replaced_apps() {
  local marker="$STATE_DIR/replaced-apps-removed" transaction extra
  local -a installed=()
  [[ -f "$marker" ]] && return 0
  mapfile -t installed < <(rpm -q --qf '%{NAME}\n' "${REPLACED_PACKAGES[@]}" 2>/dev/null | grep -v ' ')
  if ((${#installed[@]})); then
    transaction=$(LC_ALL=C sudo dnf remove --assumeno --noautoremove "${installed[@]}" 2>&1 || true)
    extra=$(removal_names <<<"$transaction" | grep -vxF -f <(printf '%s\n' "${installed[@]}") || true)
    if [[ -n "$extra" ]]; then
      warn "Not removing the replaced apps: dnf would also remove $(tr '\n' ' ' <<<"$extra")"
      return 0
    fi
    sudo dnf remove -y --noautoremove "${installed[@]}"
  fi
  mkdir -p "$STATE_DIR"
  : >"$marker"
}

install_flatpaks() {
  sudo flatpak install -y --noninteractive flathub "${FLATPAKS[@]}"
  # Cursors (and icons) installed for your user live in ~/.local/share/icons, which Flatpaks can't see otherwise.
  flatpak override --user --filesystem=xdg-data/icons:ro
}
