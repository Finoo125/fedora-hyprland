# shellcheck shell=bash
# System-wide configuration: login screen, fingerprint, snapshots, icons, services.

GREETER_DIR=/var/lib/noctalia-greeter
PAPIRUS_FOLDERS_SHA=0f838ee5679229e3a3e97e3b333c222c9e9615b4
GRUB_BTRFS_SHA=2fcfbe967637166b88dadd49c834807243a941bf # v4.14; Fedora packages no grub-btrfs

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

# greeter_toml SESSION WALLPAPER LAYOUT -> /var/lib/noctalia-greeter/greeter.toml
greeter_toml() {
  cat <<EOF
# Written by fedora-hyprland/install.sh on every run.
[session]
default = "$1"

[keyboard]
layout = "$3"

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
    "$(greeter_toml "$(greeter_session /usr/share/wayland-sessions)" "$wall" "$(keyboard_layout "$XKB_CONF")")"
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
  # Monthly scrub reads every block and checks its checksum, so a failing disk shows up before the backup is needed.
  # The weekly balance stays off: current btrfs doesn't need it and it costs a lot of disk I/O.
  sudo systemctl enable --now btrfsmaintenance-refresh.path btrfs-scrub.timer
}

# home_snapshots_possible -> 0 when /home is its own btrfs subvolume (Fedora's default layout).
home_snapshots_possible() { [[ "$(findmnt -no FSTYPE /home 2>/dev/null)" == btrfs ]]; }
home_snapshots_enabled() { sudo snapper -c home get-config >/dev/null 2>&1; }

# Hourly snapshots of /home: undo a deleted or overwritten file from Btrfs Assistant or /home/.snapshots.
# They live on the same disk, so they are no backup: Pika Backup copies to another drive or a server.
setup_home_snapshots() {
  home_snapshots_enabled || sudo snapper -c home create-config /home
  # ALLOW_USERS + SYNC_ACL let you browse and restore your own snapshots without sudo.
  sudo snapper -c home set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes TIMELINE_LIMIT_HOURLY=12 \
    TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
    "ALLOW_USERS=$USER" SYNC_ACL=yes
  sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
}

# grub_btrfs_config -> /etc/default/grub-btrfs/config, with Fedora's grub2 paths (upstream defaults to Debian/Arch's).
grub_btrfs_config() {
  cat <<'EOF'
# Written by fedora-hyprland/install.sh on every run. All options: man grub-btrfs
GRUB_BTRFS_SUBMENUNAME="Fedora snapshots"
GRUB_BTRFS_LIMIT="20"
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"
GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig
GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check
GRUB_BTRFS_MKCONFIG_LIB=/usr/share/grub/grub-mkconfig_lib
# "root" is the running system; container layers aren't bootable systems.
GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("root")
GRUB_BTRFS_IGNORE_PREFIX_PATH=("home" "root/var/lib/docker" "root/var/lib/containers" "root/var/lib/machines")
EOF
}

# A "Fedora snapshots" GRUB submenu, kept current by grub-btrfsd whenever snapper takes a snapshot.
# /boot is a separate partition, so a snapshot boots with today's kernels: pick one that was installed back then.
setup_grub_btrfs() {
  local tmp conf marker="$STATE_DIR/grub-btrfs-version"
  if [[ "$(cat "$marker" 2>/dev/null)" != "$GRUB_BTRFS_SHA" ]]; then
    tmp=$(mktemp -d)
    curl -fsSL "https://github.com/Antynea/grub-btrfs/archive/$GRUB_BTRFS_SHA.tar.gz" | tar -xz -C "$tmp" --strip-components=1
    sudo make -C "$tmp" install GRUB_UPDATE_EXCLUDE=true >/dev/null
    rm -rf "$tmp"
    # make install brings upstream's config; removing it makes the check below write ours and rebuild grub.cfg.
    sudo rm -f /etc/default/grub-btrfs/config
    mkdir -p "$STATE_DIR"
    echo "$GRUB_BTRFS_SHA" >"$marker"
  fi
  conf=$(grub_btrfs_config)
  if ! sudo test -f /etc/default/grub-btrfs/config || [[ "$(sudo cat /etc/default/grub-btrfs/config)" != "$conf" ]]; then
    write_root /etc/default/grub-btrfs/config "$conf"
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
  sudo systemctl enable --now grub-btrfsd
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

# cpu_is_intel CPUINFO -> 0 on an Intel CPU. thermald only supports Intel; on AMD it refuses to start.
cpu_is_intel() { grep -q '^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel' "$1"; }

# enabled_units PATTERN -> enabled unit files matching PATTERN, one per line. systemctl exits 1 when none match,
# which is not an error (and would fire install.sh's ERR trap from inside a process substitution).
enabled_units() { systemctl list-unit-files --state=enabled --no-legend "$1" | awk '{print $1}' || true; }

setup_system() {
  local -a abrt
  setup_greeter
  setup_fingerprint
  setup_snapper
  setup_icons
  setup_power
  sudo systemctl enable --now bluetooth cups avahi-daemon tuned tuned-ppd fwupd-refresh.timer
  if cpu_is_intel /proc/cpuinfo; then
    sudo systemctl enable --now thermald
    # Low Power Mode Daemon: keeps light work on the efficient cores of hybrid Intel CPUs (Meteor Lake and newer,
    # e.g. Panther Lake). It exits on CPUs it doesn't support, which is fine.
    sudo systemctl enable --now intel_lpmd || warn "intel_lpmd didn't start; this CPU is probably older than Meteor Lake."
  fi
  # Docker starts on first use instead of at boot, where it made boot wait ~7 s for the network.
  sudo systemctl disable docker.service
  sudo systemctl enable docker.socket
  sudo usermod -aG docker "$USER"
  # Ghostty keeps one instance running per user, so Super+Return opens windows instantly.
  sudo systemctl --global enable app-com.mitchellh.ghostty.service
  # The keyring's SSH agent: SSH keys are unlocked once at login instead of asking for the passphrase on every git push.
  # Its socket sets SSH_AUTH_SOCK for the session itself.
  sudo systemctl --global enable gcr-ssh-agent.socket
  # The Minimal Install brings abrt (crash reporting to Fedora); its daemons only cost time at boot and login.
  mapfile -t abrt < <(enabled_units 'abrt*')
  if ((${#abrt[@]})); then sudo systemctl disable --now "${abrt[@]}"; fi
  if systemctl is-active -q firewalld && ! sudo firewall-cmd --permanent --query-service=kdeconnect >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-service=kdeconnect
    sudo firewall-cmd --reload
  fi
}
