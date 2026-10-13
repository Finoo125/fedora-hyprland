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

main() {
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'warn "Stopped at line $LINENO. Full log: $LOG_FILE. Fix the problem and run ./install.sh again; finished steps are skipped."' ERR
  preflight
  log "Repositories";        setup_repos
  log "Packages";            install_packages
  log "Flatpak apps";        install_flatpaks
  log "Other apps";          install_apps
  log "Done. Reboot to start Hyprland: systemctl reboot"
}

main "$@"
