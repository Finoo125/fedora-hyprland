#!/usr/bin/env bash
# CI only, right after tests/repoquery.sh in the same fedora:44 container (its repos are already set up):
# resolves install_packages' dnf transaction without installing it and fails if a dependency would pull in
# another desktop (GNOME Shell, KDE, GDM, ...).
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
source lib/packages.sh

mapfile -t pkgs < <(main_dnf_packages)
transaction=$(LC_ALL=C dnf install -y --assumeno "${pkgs[@]}" 2>&1 || true)
grep -q '^Transaction Summary' <<<"$transaction" || { echo "$transaction"; echo "dnf could not resolve the install"; exit 1; }
foreign=$(foreign_desktop_packages <<<"$transaction")
if [[ -n "$foreign" ]]; then
  echo "These packages would pull in another desktop: $(tr '\n' ' ' <<<"$foreign")"
  echo "Find the culprit with: dnf repoquery --whatrequires <package> --recursive"
  exit 1
fi
echo "No other desktop is pulled in ($(wc -l <<<"$transaction") lines of dnf transaction checked)."
