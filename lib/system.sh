# shellcheck shell=bash
# System-wide configuration: login screen, fingerprint, snapshots, icons, services.

GREETER_DIR=/var/lib/noctalia-greeter
PAPIRUS_FOLDERS_SHA=0f838ee5679229e3a3e97e3b333c222c9e9615b4

# greeter_session SESSIONS_DIR -> session name for the greeter; prefers the uwsm-managed Hyprland session.
greeter_session() {
  if [[ -f "$1/hyprland-uwsm.desktop" ]]; then echo hyprland-uwsm; else echo hyprland; fi
}

# greeter_cmd -> full path of the greeter's session wrapper; fails if it's missing (never an empty greetd command).
greeter_cmd() { command -v noctalia-greeter-session; }

# greetd_config GREETER_CMD -> /etc/greetd/config.toml. Fedora's greetd runs greeters as user "greetd".
greetd_config() {
  cat <<EOF
# Written by fedora-hyprland/install.sh.
[terminal]
vt = 1

[default_session]
command = "$1"
user = "greetd"
EOF
}

# greeter_toml SESSION WALLPAPER -> /var/lib/noctalia-greeter/greeter.toml
greeter_toml() {
  cat <<EOF
# Written by fedora-hyprland/install.sh on every run.
[session]
default = "$1"

[keyboard]
layout = "de"

[appearance]
scheme = "Ayu"
theme_mode = "dark"
EOF
  if [[ -n "$2" ]]; then printf '\n[appearance.wallpaper]\npath = "%s"\nfill_mode = "crop"\n' "$2"; fi
}

setup_greeter() {
  local wall="" src cmd
  cmd=$(greeter_cmd) || die "noctalia-greeter-session not found, so the login screen would not start. Is Terra's noctalia-greeter installed?"
  write_root /etc/greetd/config.toml "$(greetd_config "$cmd")"
  # The greeter package's tmpfiles entry assumes a "greeter" user; Fedora's greetd user is "greetd".
  write_root /etc/tmpfiles.d/noctalia-greeter.conf "d $GREETER_DIR 0750 greetd greetd -"
  sudo systemd-tmpfiles --create /etc/tmpfiles.d/noctalia-greeter.conf
  sudo chown greetd:greetd "$GREETER_DIR"
  src=$(default_wallpaper "$REPO_DIR/config/wallpapers.txt" "$WALL_DIR")
  if [[ -f "$src" ]]; then
    wall="$GREETER_DIR/wallpaper.${src##*.}"
    sudo install -m 644 -o greetd -g greetd "$src" "$wall"
  fi
  write_root "$GREETER_DIR/greeter.toml" \
    "$(greeter_toml "$(greeter_session /usr/share/wayland-sessions)" "$wall")"
  sudo chown greetd:greetd "$GREETER_DIR/greeter.toml"
  sudo systemctl enable greetd
  sudo systemctl set-default graphical.target
}

setup_fingerprint() {
  sudo authselect current >/dev/null 2>&1 || sudo authselect select local --force
  sudo authselect enable-feature with-fingerprint
  sudo authselect apply-changes
}

setup_snapper() {
  if [[ "$(findmnt -no FSTYPE /)" != btrfs ]]; then
    warn "/ is not on btrfs, so automatic snapshots are skipped."
    return 0
  fi
  sudo snapper -c root get-config >/dev/null 2>&1 || sudo snapper -c root create-config /
  sudo snapper -c root set-config NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_CREATE=no
  sudo install -D -m 644 "$REPO_DIR/config/snapper.actions" /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
}

# Gold folders in Papirus-Dark to match Ayu (papirus-folders is a single script, pinned to a commit).
setup_icons() {
  local script
  script=$(mktemp)
  curl -fsSL -o "$script" \
    "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/$PAPIRUS_FOLDERS_SHA/papirus-folders"
  sudo bash "$script" -C yellow --theme Papirus-Dark
  rm -f "$script"
}

# tuned_ppd_conf -> /etc/tuned/ppd.conf. Noctalia's power toggle talks to tuned-ppd. Fedora maps "balanced" to
# balanced-battery when unplugged, which roughly doubles app start times; here "balanced" means full speed on AC
# and plain balanced on battery. Power saver stays available for long battery days. tuned-ppd refuses to start
# when two PPD profiles map to the same TuneD profile, so performance uses accelerator-performance (throughput-performance
# plus shallow C-states only).
tuned_ppd_conf() {
  cat <<EOF
# Written by fedora-hyprland/install.sh.
[main]
# The default PPD profile
default=balanced
battery_detection=true
sysfs_acpi_monitor=true

[profiles]
# PPD = TuneD
power-saver=powersave
balanced=throughput-performance
performance=accelerator-performance

[battery]
# PPD = TuneD
balanced=balanced
EOF
}

setup_power() {
  local conf
  conf=$(tuned_ppd_conf)
  if sudo test -f /etc/tuned/ppd.conf && [[ "$(sudo cat /etc/tuned/ppd.conf)" == "$conf" ]]; then return 0; fi
  write_root /etc/tuned/ppd.conf "$conf"
  sudo systemctl try-restart tuned-ppd
}

# enabled_units PATTERN -> enabled unit files matching PATTERN, one per line.
enabled_units() { systemctl list-unit-files --state=enabled --no-legend "$1" | awk '{print $1}'; }

setup_system() {
  local -a abrt
  setup_greeter
  setup_fingerprint
  setup_snapper
  setup_icons
  setup_power
  sudo systemctl enable --now bluetooth cups avahi-daemon tuned tuned-ppd thermald fwupd-refresh.timer
  # Docker starts on first use instead of at boot, where it made boot wait ~7 s for the network.
  sudo systemctl disable docker.service
  sudo systemctl enable docker.socket
  sudo usermod -aG docker "$USER"
  # Ghostty keeps one instance running per user, so Super+Return opens windows instantly.
  sudo systemctl --global enable app-com.mitchellh.ghostty.service
  # The Minimal Install brings abrt (crash reporting to Fedora); its daemons only cost time at boot and login.
  mapfile -t abrt < <(enabled_units 'abrt*')
  if ((${#abrt[@]})); then sudo systemctl disable --now "${abrt[@]}"; fi
  if systemctl is-active -q firewalld && ! sudo firewall-cmd --permanent --query-service=kdeconnect >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-service=kdeconnect
    sudo firewall-cmd --reload
  fi
}
