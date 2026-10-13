#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh

update=$(cat bin/update)
assert_true "firmware updates never reboot in the middle of update" grep -qF 'fwupdmgr update -y --no-reboot-check' <<<"$update"
finish
