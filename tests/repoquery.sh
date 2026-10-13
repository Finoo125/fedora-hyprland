#!/usr/bin/env bash
# CI only (fedora:44 container, runs as root): adds the installer's repos with the real setup_repos,
# then checks that every dnf package and Flatpak the installer wants actually exists.
set -euo pipefail
cd "$(dirname "$0")/.."
dnf install -y sudo
source lib/common.sh
source lib/packages.sh
setup_repos

dnf repo list --enabled | grep -q '^terra ' || { echo "Terra repo is not enabled"; exit 1; }
if dnf repo list --enabled | terra_extra_repos | grep -q .; then echo "A Terra extra repo is still enabled"; exit 1; fi

mapfile -t wanted < <(all_dnf_packages)
# -y like install.sh: Terra signs its repo metadata (repo_gpgcheck=1), and importing that key needs a yes.
available=$(dnf repoquery -y --available --qf '%{name}.%{arch}\n' "${wanted[@]}")
missing=0
for p in "${wanted[@]}"; do
  if [[ "$p" == *.i686 ]]; then pattern="^${p//./\\.}$"; else pattern="^${p//./\\.}\\."; fi
  grep -qE "$pattern" <<<"$available" || { echo "missing dnf package: $p"; missing=1; }
done
for app in "${FLATPAKS[@]}"; do
  flatpak remote-info flathub "$app" >/dev/null 2>&1 || { echo "missing flatpak: $app"; missing=1; }
done
exit $missing
