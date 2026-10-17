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
  gnome-keyring gnome-keyring-pam dconf ddcutil bolt polkit qt5-qtwayland qt6-qtwayland qt6ct nwg-look adw-gtk3-theme papirus-icon-theme
  xsettingsd google-noto-sans-fonts google-noto-color-emoji-fonts jetbrains-mono-fonts-all
  google-noto-sans-cjk-fonts liberation-fonts-all wl-clipboard grim slurp hyprpicker gpu-screen-recorder udiskie
  xdg-user-dirs xdg-utils xdg-terminal-exec libnotify playerctl brightnessctl)
DNF_APPS=(ghostty Thunar thunar-archive-plugin thunar-volman tumbler ffmpegthumbnailer
  file-roller firefox mpv mpv-mpris qview papers gnome-text-editor gnome-calculator gnome-software kde-connect
  pavucontrol gnome-disk-utility thunderbird vlc telegram-desktop discord flatseal
  signal-desktop heroic-games-launcher protonplus faugus-launcher mission-center)
# GParted requires a polkit agent package; Noctalia is the agent but its RPM doesn't say so, and dnf would
# pull in all of GNOME Shell instead. xfce-polkit (42 KB) satisfies it and only autostarts on XFCE.
# Drives, network shares and devices in Thunar. gvfs-fuse gives smb://, mtp:// etc. a real path under
# /run/user/$UID/gvfs so non-GTK apps (qView, mpv, ...) can open files there too.
DNF_STORAGE=(gparted xfce-polkit gvfs gvfs-fuse gvfs-smb gvfs-nfs gvfs-mtp gvfs-afc gvfs-gphoto2 gvfs-archive
  udisks2 udisks2-btrfs ntfs-3g exfatprogs dosfstools udftools hfsplus-tools btrfs-progs xfsprogs
  cifs-utils nfs-utils samba-client fuse-sshfs libimobiledevice-utils ifuse unrar)
DNF_CLI=(git gh wget2-wget curl fastfetch btop bat eza fzf ripgrep fd-find zoxide unzip 7zip bash-completion plocate rsync ImageMagick)
DNF_MEDIA=(intel-media-driver libva-utils)
# AMD only: Fedora's mesa leaves out H.264/HEVC hardware decoding, RPM Fusion's build has it.
DNF_AMD=(mesa-va-drivers-freeworld)
DNF_GAMING=(steam gamemode mangohud gamescope lutris protontricks winetricks vulkan-tools)
DNF_SYSTEM=(fuse-libs cups cups-pk-helper cups-pdf hplip gutenprint-cups foomatic-db system-config-printer avahi nss-mdns
  NetworkManager-openvpn-gnome NetworkManager-openconnect-gnome wireguard-tools fprintd fprintd-pam
  snapper btrfs-assistant btrfsmaintenance smartmontools libdnf5-plugin-actions fwupd thermald inotify-tools)
DNF_DEV=(gcc make uv python3 python3.12 python3.13 nodejs24 nodejs24-npm podman distrobox code
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
DNF_NVIDIA=(akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-power
  libva-nvidia-driver switcheroo-control)
DNF_SECUREBOOT=(kmodtool akmods mokutil openssl)
# Only apps without an RPM in Fedora, RPM Fusion or Terra; everything else comes from dnf.
FLATPAKS=(com.rtosta.zapzap com.bitwarden.desktop md.obsidian.Obsidian io.dbeaver.DBeaverCommunity
  org.localsend.localsend_app it.mijorus.gearlever org.gnome.World.PikaBackup)

# all_dnf_packages -> every dnf package the installer may install, one per line (CI checks they exist).
all_dnf_packages() {
  printf '%s\n' "${DNF_BASE[@]}" "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_STORAGE[@]}" "${DNF_CLI[@]}" "${DNF_MEDIA[@]}" \
    "${DNF_GAMING[@]}" "${DNF_SYSTEM[@]}" "${DNF_DEV[@]}" "${DNF_NVIDIA[@]}" "${DNF_SECUREBOOT[@]}" "${DNF_AMD[@]}" ffmpeg
}

# main_dnf_packages -> the packages install_packages installs in one dnf transaction, one per line.
main_dnf_packages() {
  printf '%s\n' "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_STORAGE[@]}" "${DNF_CLI[@]}" "${DNF_SYSTEM[@]}" \
    "${DNF_GAMING[@]}" "${DNF_DEV[@]}"
}

# Other desktops' shells, sessions and login managers. A dependency that drags one in (as GParted once did
# with GNOME Shell) installs hundreds of MB the Hyprland setup never uses.
FOREIGN_DESKTOP=(gnome-shell gnome-session mutter gdm kwin plasma-workspace sddm cinnamon xfce4-session
  mate-session-manager lightdm)

# foreign_desktop_packages: stdin = `dnf install --assumeno` output -> the FOREIGN_DESKTOP packages it would install.
foreign_desktop_packages() {
  awk 'NF >= 5 {print $1}' | grep -xF -f <(printf '%s\n' "${FOREIGN_DESKTOP[@]}") || true
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
}

install_flatpaks() {
  sudo flatpak install -y --noninteractive flathub "${FLATPAKS[@]}"
}
