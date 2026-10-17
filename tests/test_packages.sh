#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/packages.sh

repo_list='repo id                 repo name                          status
fedora                  Fedora 44 - x86_64                 enabled
terra                   Terra 44                           enabled
terra-extras            Terra 44 (Extras)                  enabled
terra-mesa              Terra 44 (Mesa)                    disabled
updates                 Fedora 44 - x86_64 - Updates       enabled'
assert_eq $'terra-extras\nterra-mesa' "$(terra_extra_repos <<<"$repo_list")" "only Terra's extra repos get disabled"

all=$(all_dnf_packages)
assert_true  "hyprland is in the list"        grep -qx hyprland <<<"$all"
assert_true  "noctalia is in the list"        grep -qx noctalia <<<"$all"
assert_true  "NVIDIA packages are checked too" grep -qx akmod-nvidia <<<"$all"
assert_false "cliphist is not needed"         grep -qx cliphist <<<"$all"
assert_true  "dconf is installed so gsettings really saves" grep -qx dconf <<<"$all"
assert_eq "$(sort <<<"$all" | uniq -d)" "" "no package is listed twice"
assert_true  "the login unlocks the keyring"   grep -qx gnome-keyring-pam <<<"$all"
assert_true  "NAS files open in non-GTK apps"  grep -qx gvfs-fuse <<<"$all"
assert_true  "btrfs gets scrubbed"             grep -qx btrfsmaintenance <<<"$all"

for pkg in signal-desktop heroic-games-launcher protonplus faugus-launcher mission-center; do
  assert_true "Terra allows $pkg" grep -q "\b$pkg\*" <<<"$TERRA_ALLOW"
done
assert_false "Signal comes from Terra, not Flathub" grep -qx org.signal.Signal < <(printf '%s\n' "${FLATPAKS[@]}")
assert_false "Discord comes from RPM Fusion, not Flathub" grep -qx com.discordapp.Discord < <(printf '%s\n' "${FLATPAKS[@]}")

transaction=' Package                Arch   Version            Repository      Size
Installing:
 gparted               x86_64 1.7.0-3.fc44       fedora       6.8 MiB
Installing dependencies:
 gnome-shell           x86_64 50.6-1.fc44        updates     12.0 MiB
 gnome-shell-common    noarch 50.6-1.fc44        updates     16.4 KiB
 gdm                   x86_64 50.0-1.fc44        updates      5.1 MiB
Transaction Summary:
 Installing:         4 packages'
assert_eq $'gnome-shell\ngdm' "$(foreign_desktop_packages <<<"$transaction")" "a pulled-in GNOME Shell and GDM are caught"
assert_eq "" "$(grep -v 'gdm ' <<<"$transaction" | grep -v ' gnome-shell  ' | foreign_desktop_packages)" "gnome-shell-common alone is no desktop"
assert_eq "" "$(grep -vE 'gnome-shell |gdm ' <<<"$transaction" | foreign_desktop_packages)" "a clean transaction passes"
main=$(main_dnf_packages)
assert_true  "the main install includes GParted"            grep -qx gparted <<<"$main"
assert_true  "GParted comes with a tiny polkit agent"       grep -qx xfce-polkit <<<"$main"
assert_false "NVIDIA drivers are not in the main install"   grep -qx akmod-nvidia <<<"$main"

amd='03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] (rev c1)'
intel='00:02.0 VGA compatible controller: Intel Corporation Alder Lake-UP3 GT2 [Iris Xe Graphics] (rev 0c)'
nvidia='01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q / Mobile] (rev a1)'
assert_true  "an AMD GPU is found"                  has_amd_gpu "$amd"
assert_true  "an AMD GPU next to NVIDIA is found"   has_amd_gpu "$amd"$'\n'"$nvidia"
assert_false "Intel graphics are not AMD"           has_amd_gpu "$intel"
assert_false "NVIDIA is not AMD"                    has_amd_gpu "$nvidia"

portals=config/xdg-desktop-portal/hyprland-portals.conf
assert_true "portals keep Fedora's hyprland;gtk default" grep -qx 'default=hyprland;gtk' "$portals"
assert_true "secrets go to gnome-keyring" grep -qx 'org.freedesktop.impl.portal.Secret=gnome-keyring' "$portals"
assert_true "gnome-keyring ships that portal" grep -qx gnome-keyring <<<"$(printf '%s\n' "${DNF_DESKTOP[@]}")"
finish
