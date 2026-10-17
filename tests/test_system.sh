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

mkdir -p "$tmp/bin" "$tmp/nobin"
printf '#!/bin/sh\n' >"$tmp/bin/noctalia-greeter-session"; chmod +x "$tmp/bin/noctalia-greeter-session"
assert_eq "$tmp/bin/noctalia-greeter-session" "$(PATH="$tmp/bin" greeter_cmd)" "greeter wrapper is found on PATH"
PATH="$tmp/nobin" assert_false "a missing greeter wrapper is an error, never an empty command" greeter_cmd

conf=$(greetd_config /usr/bin/noctalia-greeter-session)
assert_true "greetd starts the greeter session wrapper" grep -qx 'command = "/usr/bin/noctalia-greeter-session"' <<<"$conf"
assert_true "greetd uses Fedora's greetd user"         grep -qx 'user = "greetd"' <<<"$conf"

toml=$(greeter_toml hyprland-uwsm /var/lib/noctalia-greeter/wallpaper.jpg fr)
assert_true "greeter keyboard is the system's" grep -qx 'layout = "fr"' <<<"$toml"
assert_true "greeter default session"  grep -qx 'default = "hyprland-uwsm"' <<<"$toml"
assert_true "greeter uses Ayu"         grep -qx 'scheme = "Ayu"' <<<"$toml"
assert_true "greeter wallpaper"        grep -qx 'path = "/var/lib/noctalia-greeter/wallpaper.jpg"' <<<"$toml"
assert_false "no wallpaper section without a wallpaper" grep -q 'appearance.wallpaper' <<<"$(greeter_toml hyprland '' us)"

gb=$(grub_btrfs_config)
assert_true "grub-btrfs uses Fedora's grub2-mkconfig" grep -qx 'GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig' <<<"$gb"
assert_true "grub-btrfs writes to /boot/grub2"         grep -qx 'GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"' <<<"$gb"
assert_true "the running system is not a snapshot entry" grep -qx 'GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("root")' <<<"$gb"
assert_true "the config is valid bash" bash -n <<<"$gb"

ppd=$(tuned_ppd_conf)
assert_eq "balanced=throughput-performance" "$(sed -n '/^\[profiles\]/,/^\[/p' <<<"$ppd" | grep '^balanced=')" "balanced runs at full speed on AC"
assert_eq "balanced=balanced" "$(sed -n '/^\[battery\]/,$p' <<<"$ppd" | grep '^balanced=')" "balanced on battery is plain balanced, not balanced-battery"
assert_true "power saver is still available" grep -qx 'power-saver=powersave' <<<"$ppd"
# tuned-ppd exits with "Duplicate profile mapping" unless every PPD profile maps to its own TuneD profile.
assert_eq "" "$(sed -n '/^\[profiles\]/,/^\[/p' <<<"$ppd" | grep -v '^#' | grep '=' | cut -d= -f2 | sort | uniq -d)" "no TuneD profile is mapped twice on AC"
printf 'processor\t: 0\nvendor_id\t: GenuineIntel\n' >"$tmp/intel"
printf 'processor\t: 0\nvendor_id\t: AuthenticAMD\n' >"$tmp/amd"
assert_true  "Intel CPU gets thermald" cpu_is_intel "$tmp/intel"
assert_false "AMD CPU skips thermald"  cpu_is_intel "$tmp/amd"
finish
