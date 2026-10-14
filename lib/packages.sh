# shellcheck shell=bash
# Package sources and package lists. Every function here is safe to run again.

COPR_REPO="lionheartp/Hyprland"
TERRA_ALLOW="noctalia-greeter*,ghostty*,bibata-cursor-theme*"
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
  gnome-keyring dconf ddcutil bolt polkit qt5-qtwayland qt6-qtwayland qt6ct nwg-look adw-gtk3-theme papirus-icon-theme
  bibata-cursor-theme xsettingsd google-noto-sans-fonts google-noto-color-emoji-fonts jetbrains-mono-fonts-all
  wl-clipboard grim slurp hyprpicker xdg-user-dirs xdg-utils)
DNF_APPS=(ghostty Thunar thunar-archive-plugin thunar-volman tumbler ffmpegthumbnailer gvfs gvfs-mtp gvfs-smb
  file-roller firefox mpv qview papers gnome-text-editor gnome-calculator gnome-software kde-connect)
DNF_CLI=(git gh wget2-wget curl fastfetch btop bat eza fzf ripgrep fd-find zoxide unzip 7zip bash-completion plocate)
DNF_MEDIA=(intel-media-driver libva-utils)
DNF_GAMING=(steam gamemode mangohud gamescope lutris protontricks winetricks vulkan-tools)
DNF_SYSTEM=(fuse-libs cups system-config-printer avahi nss-mdns fprintd fprintd-pam snapper btrfs-assistant
  libdnf5-plugin-actions fwupd thermald)
DNF_DEV=(gcc make uv python3 python3.12 python3.13 nodejs24 nodejs24-npm podman distrobox code
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
DNF_NVIDIA=(akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-power
  libva-nvidia-driver switcheroo-control)
DNF_SECUREBOOT=(kmodtool akmods mokutil openssl)
FLATPAKS=(com.discordapp.Discord org.signal.Signal org.telegram.desktop com.rtosta.zapzap org.mozilla.Thunderbird
  org.videolan.VLC com.bitwarden.desktop md.obsidian.Obsidian io.dbeaver.DBeaverCommunity org.localsend.localsend_app
  com.vysp3r.ProtonPlus com.heroicgameslauncher.hgl io.github.Faugus.faugus-launcher it.mijorus.gearlever
  com.github.tchx84.Flatseal io.missioncenter.MissionCenter)

# all_dnf_packages -> every dnf package the installer may install, one per line (CI checks they exist).
all_dnf_packages() {
  printf '%s\n' "${DNF_BASE[@]}" "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_CLI[@]}" "${DNF_MEDIA[@]}" \
    "${DNF_GAMING[@]}" "${DNF_SYSTEM[@]}" "${DNF_DEV[@]}" "${DNF_NVIDIA[@]}" "${DNF_SECUREBOOT[@]}" ffmpeg
}

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
  # Terra only provides the greeter, Ghostty and the Bibata cursor; nothing else from it may replace Fedora packages.
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
  sudo dnf install -y "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_CLI[@]}" "${DNF_SYSTEM[@]}" \
    "${DNF_GAMING[@]}" "${DNF_DEV[@]}"
  # RPM Fusion's full ffmpeg replaces Fedora's ffmpeg-free; the multimedia group adds the matching GStreamer plugins.
  sudo dnf install -y --allowerasing ffmpeg
  sudo dnf group install -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
  sudo dnf install -y "${DNF_MEDIA[@]}"
  # Minimal Install leaves out the firmware for Wi-Fi, Bluetooth and audio chips (e.g. Intel iwlwifi).
  sudo dnf group install -y hardware-support
}

install_flatpaks() {
  sudo flatpak install -y --noninteractive flathub "${FLATPAKS[@]}"
}
