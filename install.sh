#!/usr/bin/env bash
# fedora-hyprland: turns a fresh Fedora 44 Minimal install into a Hyprland + Noctalia v5 desktop.
# Usage: ./install.sh   (as your normal user; re-running is safe and is how updates are applied)
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"
for lib in "$REPO_DIR"/lib/*.sh; do
  [[ "$lib" == */common.sh ]] && continue
  # shellcheck source=/dev/null
  source "$lib"
done

preflight() {
  [[ $EUID -ne 0 ]] || die "Run this as your normal user, not with sudo. It asks for your password when it needs it."
  fedora_version_ok /etc/os-release || die "This installer needs Fedora 44 or newer."
  curl -fsI --max-time 15 https://fedoraproject.org >/dev/null || die "No internet connection. Connect with nmtui, then run it again."
  sudo -v
  # Keep sudo's timestamp fresh for the whole run.
  while sleep 50; do sudo -n true; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
}

# Questions asked at the end; a "no" is remembered so later runs (and `update`) don't ask again.
optional_steps() {
  local fp
  fp=$(fprintd-list "$USER" 2>&1 || true)
  if grep -q 'no fingers enrolled' <<<"$fp" && ask_once fingerprint "Enroll a fingerprint now (sudo, login, lock screen)?" y; then
    # As root: enrolling needs a polkit agent for the user, and a text console (first install) has none.
    sudo fprintd-enroll "$USER" || warn "Fingerprint enrollment didn't finish. Run fprintd-enroll later."
  fi
  if home_snapshots_possible; then
    if home_snapshots_enabled; then
      setup_home_snapshots
    elif ask_once home-snapshots "Take hourly snapshots of /home, so deleted files can be restored (kept 7 days)?" y; then
      setup_home_snapshots
    fi
  fi
  # Once installed, every run keeps grub-btrfs current; the question only comes the first time.
  if sudo snapper -c root get-config >/dev/null 2>&1 && { [[ -f "$STATE_DIR/grub-btrfs-version" ]] ||
    ask_once grub-btrfs "Add system snapshots to the boot menu, to start the system as it was before an update?" y; }; then
    setup_grub_btrfs
  fi
  if [[ ! -f "$ARTCRAFT_APPIMAGE" ]] && ask_once artcraft "Install the ArtCraft Launcher (alpha creative apps)?" n; then
    install_artcraft
  fi
}

main() {
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'warn "Stopped at line $LINENO. Full log: $LOG_FILE. Fix the problem and run ./install.sh again; finished steps are skipped."' ERR
  preflight
  log "Language and keyboard"; setup_locale
  log "Repositories";        setup_repos
  log "Packages";            install_packages
  log "Flatpak apps";        install_flatpaks
  log "Other apps";          install_apps
  log "Your configuration";  setup_user
  log "System";              setup_system
  log "NVIDIA";              setup_nvidia
  log "Optional steps";      optional_steps
  log "Done. Reboot to start Hyprland: systemctl reboot"
}

main "$@"
