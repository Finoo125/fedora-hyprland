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
finish
