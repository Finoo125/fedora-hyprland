#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/locale.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/kb.conf" <<'CONF'
# Written by systemd-localed(8)
Section "InputClass"
        Identifier "system-keyboard"
        Option "XkbLayout" "de,us"
        Option "XkbModel" "pc105"
        Option "XkbVariant" "nodeadkeys,"
EndSection
CONF
assert_eq "de,us" "$(xkb_option "$tmp/kb.conf" Layout)" "xkb_option reads the layout"
assert_eq "nodeadkeys," "$(xkb_option "$tmp/kb.conf" Variant)" "xkb_option reads the variant"
assert_eq "" "$(xkb_option "$tmp/kb.conf" Options)" "a missing option is empty"
assert_eq "de" "$(keyboard_layout "$tmp/kb.conf")" "the first layout is the main one"
assert_eq "us" "$(keyboard_layout "$tmp/missing.conf")" "no keyboard file: US layout"

assert_eq "langpacks-de" "$(langpack_for de_DE.UTF-8)" "German langpack"
assert_eq "langpacks-en" "$(langpack_for en_GB.UTF-8)" "English langpack, whatever the country"
assert_eq "langpacks-pt_BR" "$(langpack_for pt_BR.UTF-8)" "Brazilian Portuguese has its own langpack"
assert_eq "langpacks-sr" "$(langpack_for sr_RS.UTF-8@latin)" "modifiers are dropped"

choices() { printf '%s\n' us de fr; }
assert_eq "fr" "$(ask_value "Layout?" us choices <<<"fr")" "a known answer is taken"
assert_eq "us" "$(ask_value "Layout?" us choices <<<"")" "Enter takes the default"
assert_eq "de" "$(ask_value "Layout?" us choices 2>/dev/null <<<$'xx\nde')" "an unknown answer is asked again"
assert_eq "none" "$(ask_value "Variant?" none choices <<<"")" "none is always accepted"
finish
