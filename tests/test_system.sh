#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/system.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
touch "$tmp/hyprland.desktop"
assert_eq "hyprland" "$(greeter_session "$tmp")" "plain Hyprland session when uwsm's is missing"
touch "$tmp/hyprland-uwsm.desktop"
assert_eq "hyprland-uwsm" "$(greeter_session "$tmp")" "uwsm-managed session is preferred"

conf=$(greetd_config /usr/bin/noctalia-greeter-session)
assert_true "greetd starts the greeter session wrapper" grep -qx 'command = "/usr/bin/noctalia-greeter-session"' <<<"$conf"
assert_true "greetd uses Fedora's greetd user"         grep -qx 'user = "greetd"' <<<"$conf"

toml=$(greeter_toml de nodeadkeys hyprland-uwsm /var/lib/noctalia-greeter/wallpaper.jpg)
assert_true "greeter keyboard layout"  grep -qx 'layout = "de"' <<<"$toml"
assert_true "greeter keyboard variant" grep -qx 'variant = "nodeadkeys"' <<<"$toml"
assert_true "greeter default session"  grep -qx 'default = "hyprland-uwsm"' <<<"$toml"
assert_true "greeter uses Ayu"         grep -qx 'scheme = "Ayu"' <<<"$toml"
assert_true "greeter wallpaper"        grep -qx 'path = "/var/lib/noctalia-greeter/wallpaper.jpg"' <<<"$toml"
assert_false "no wallpaper section without a wallpaper" grep -q 'appearance.wallpaper' <<<"$(greeter_toml us '' hyprland '')"
finish
