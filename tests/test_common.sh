#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

printf 'ID=fedora\nVERSION_ID=44\n' >"$tmp/f44"
printf 'ID=fedora\nVERSION_ID=45\n' >"$tmp/f45"
printf 'ID=fedora\nVERSION_ID=43\n' >"$tmp/f43"
printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$tmp/ubuntu"
assert_true  "Fedora 44 is accepted" fedora_version_ok "$tmp/f44"
assert_true  "Fedora 45 is accepted" fedora_version_ok "$tmp/f45"
assert_false "Fedora 43 is rejected" fedora_version_ok "$tmp/f43"
assert_false "Ubuntu is rejected"    fedora_version_ok "$tmp/ubuntu"

echo user >"$tmp/dest"; echo repo >"$tmp/src"
copy_once "$tmp/src" "$tmp/dest"
assert_eq "user" "$(cat "$tmp/dest")" "copy_once keeps an existing file"
copy_once "$tmp/src" "$tmp/new/dir/file"
assert_eq "repo" "$(cat "$tmp/new/dir/file")" "copy_once creates missing files and folders"

write_once "$tmp/dest" "generated"
assert_eq "user" "$(cat "$tmp/dest")" "write_once keeps an existing file"
write_once "$tmp/gen/file" "generated"
assert_eq "generated" "$(cat "$tmp/gen/file")" "write_once creates missing files"

ASSUME=yes; assert_true  "ASSUME=yes answers yes" ask "Question?" n
ASSUME=no;  assert_false "ASSUME=no answers no"   ask "Question?" y

STATE_DIR="$tmp/state"
ASSUME=no;  assert_false "ask_once: a no is returned"        ask_once demo "Question?" y
ASSUME=yes; assert_false "ask_once: a remembered no is kept" ask_once demo "Question?" y
ASSUME=yes; assert_true  "ask_once: other keys still ask"    ask_once other "Question?" n
unset ASSUME
finish
