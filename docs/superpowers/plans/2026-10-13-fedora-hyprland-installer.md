# Fedora Hyprland Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public repo whose `install.sh` turns a fresh Fedora 44 Minimal install into a complete Hyprland + Noctalia v5 desktop (CachyOS `cachyos-hypr-noctalia` feel), identical on both laptops, with optional NVIDIA support.

**Architecture:** `install.sh` orchestrates idempotent bash sections that live in `lib/*.sh` (one file per area; files only define functions and constants, nothing runs when sourced, so tests can source them). Defaults live in `config/` inside the cloned repo; the user's `~/.config` files are created once and then belong to the user. Hyprland is configured in Lua (Hyprland ≥ 0.55 `hl.*` API); pure decision logic is split into functions that a stubbed-`hl` Lua test exercises.

**Tech Stack:** bash 5, dnf5, flatpak, Hyprland 0.56 Lua config, Noctalia v5 TOML, greetd + noctalia-greeter, snapper, GitHub Actions (shellcheck, lua5.4, fedora:44 container).

**Spec:** `docs/superpowers/specs/2026-10-13-fedora-hyprland-installer-design.md`

## Global Constraints

- Target: Fedora 44 or newer (`ID=fedora`, `VERSION_ID >= 44`); run as the normal user, the script calls `sudo` itself.
- Package sources, exactly: Fedora 44; RPM Fusion free + nonfree; COPR `lionheartp/Hyprland`; Terra limited to `noctalia-greeter*,ghostty*,bibata-cursor-theme*` with every other `terra-*` repo disabled; Docker CE repo; Microsoft VS Code repo; Flathub (system remote).
- User files in `~/.config` are created once and never overwritten (`copy_once` / `write_once`). Files the installer owns (`/etc/...`, `/var/lib/noctalia-greeter/greeter.toml`, `~/.config/hypr/gpu.lua`, `~/.config/noctalia/10-fedora-hyprland-local.toml`) are regenerated on every run.
- Optional prompts (fingerprint, ArtCraft, NVIDIA) appear only while the item is not set up; a "no" is remembered (`ask_once`), so `update` → `install.sh` re-runs stay non-interactive.
- Third-party wallpapers and CachyOS files are never committed. Wallpapers are downloaded from raw GitHub URLs pinned to commit SHAs.
- Monitors are matched by EDID description: `desc:HP Inc. HP E27q G5` (portrait, left, `position = "0x0"`, `transform = 3`) and `desc:HP Inc. HP X27i` (main, `mode = "highrr"`, `position = "1440x0"`).
- Fedora's greetd runs greeters as user **`greetd`** (not `greeter` as upstream docs say).
- Never set `nvidia-drm.modeset` manually (RPM Fusion: conflicts with Fedora's simpledrm patch).
- All shell code passes `shellcheck`; all files use LF line endings (`.gitattributes` already enforces this).

## Deviations from the spec (decided while researching for this plan)

- The single `install.sh` is split into `install.sh` + `lib/*.sh` (same behavior, testable units).
- `cliphist` is dropped: Noctalia v5 has its own clipboard history (`[shell] clipboard_*`).
- Package renames in Fedora 44: `p7zip` → `7zip`, `wget` → `wget2-wget`.
- KDE Connect bar plugin: `icefish/phone-connect` from Noctalia's default community plugin source (enabled declaratively).
- ArtCraft gets our own `.desktop` entry instead of Gear Lever's CLI (the spec's fallback; removes an unverified dependency).
- `Super+J`: CachyOS's `togglesplit` only exists in the dwindle layout; with the master layout it becomes `swapwithmaster`.
- Noctalia idle defaults are added (lock 10 min, screens off 11 min, lock + suspend 30 min); Noctalia's built-in default is "never lock".

## Review Focus

1. Unplugging the last external monitor while the laptop panel is disabled: Hyprland briefly creates a `FALLBACK` output; the dock logic must still turn `eDP-1` back on (no black screen). Test in Task 4.
2. Re-running `install.sh` (every `update`) must not overwrite `~/.config/hypr/hyprland.lua`, Ghostty or GTK configs the user edited. Tests in Tasks 1 and 5.
3. A Minimal install where `localectl` only has a console keymap (`VC Keymap: de-nodeadkeys`, `X11 Layout: (unset)`): Hyprland and the greeter must still get `de` / `nodeadkeys`, not fall back to US. Test in Task 5.
4. A wallpaper URL that fails (offline, 404) must not abort the install or leave half-written files. Test in Task 5.
5. GTX 16-series cards are Turing (`TU116`/`TU117`) and must be treated as supported, while `GP1xx` (GTX 10) must be reported as legacy, not silently installed. Test in Task 7.

---

### Task 1: Repo skeleton, shared helpers, test harness, CI

**Files:**
- Create: `lib/common.sh`, `install.sh`, `tests/lib.sh`, `tests/run.sh`, `tests/test_common.sh`, `.github/workflows/ci.yml`, `.shellcheckrc`, `LICENSE`

**Interfaces:**
- Produces (used by every later task): `REPO_DIR`, `LOG_FILE`, `STATE_DIR`; `log MSG`, `warn MSG`, `die MSG`, `have CMD`; `ask QUESTION [y|n]` (0 = yes; `ASSUME=yes|no` answers unattended); `ask_once KEY QUESTION [y|n]` (remembers "no" in `$STATE_DIR/declined-KEY`); `copy_once SRC DEST`; `write_once DEST CONTENT`; `write_root FILE CONTENT`; `fedora_version_ok OS_RELEASE_FILE`.
- Test helpers: `assert_eq EXPECTED ACTUAL MSG`, `assert_true MSG CMD...`, `assert_false MSG CMD...`, `finish`.
- `install.sh` sources `lib/common.sh`, then every other `lib/*.sh`; later tasks add one call line each inside `main()`.

- [ ] **Step 1: Write the test harness**

`tests/lib.sh`:
```bash
# shellcheck shell=bash
# Minimal assert helpers for the bash unit tests. Usage: source tests/lib.sh; ...; finish
FAILS=0
assert_eq() { # EXPECTED ACTUAL MESSAGE
  if [[ "$1" == "$2" ]]; then
    printf 'ok   %s\n' "$3"
  else
    printf 'FAIL %s\n     expected: %q\n     actual:   %q\n' "$3" "$1" "$2"
    FAILS=$((FAILS + 1))
  fi
}
assert_true() { # MESSAGE COMMAND...
  local msg="$1"; shift
  if "$@"; then printf 'ok   %s\n' "$msg"; else printf 'FAIL %s\n' "$msg"; FAILS=$((FAILS + 1)); fi
}
assert_false() { # MESSAGE COMMAND...
  local msg="$1"; shift
  if "$@"; then printf 'FAIL %s\n' "$msg"; FAILS=$((FAILS + 1)); else printf 'ok   %s\n' "$msg"; fi
}
finish() {
  if [[ $FAILS -eq 0 ]]; then echo "all passed"; else echo "$FAILS failed"; exit 1; fi
}
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
# Runs every bash unit test. Usage: bash tests/run.sh
cd "$(dirname "$0")/.." || exit 1
rc=0
for t in tests/test_*.sh; do
  echo "--- $t"
  bash "$t" || rc=1
done
exit $rc
```

- [ ] **Step 2: Write the failing tests for common.sh**

`tests/test_common.sh`:
```bash
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL, `lib/common.sh: No such file or directory`.

- [ ] **Step 4: Implement lib/common.sh**

```bash
# shellcheck shell=bash
# Shared helpers for install.sh and bin/update. Only definitions: nothing runs when this file is sourced.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/fedora-hyprland/install.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fedora-hyprland"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ask QUESTION [DEFAULT y|n] -> status 0 for yes. ASSUME=yes|no answers without asking (unattended runs).
ask() {
  local question="$1" default="${2:-n}" hint="[y/N]" reply=""
  if [[ -n "${ASSUME:-}" ]]; then [[ "$ASSUME" == yes ]]; return; fi
  [[ "$default" == y ]] && hint="[Y/n]"
  read -r -p "$question $hint " reply || true
  [[ "${reply:-$default}" =~ ^[Yy] ]]
}

# ask_once KEY QUESTION [DEFAULT] -> like ask, but a "no" is remembered so later runs don't ask again.
ask_once() {
  local marker="$STATE_DIR/declined-$1"
  [[ -f "$marker" ]] && return 1
  if ask "$2" "${3:-n}"; then return 0; fi
  mkdir -p "$STATE_DIR"
  : >"$marker"
  return 1
}

# copy_once SRC DEST: copy only when DEST doesn't exist yet. Never overwrites the user's files.
copy_once() {
  [[ -e "$2" ]] && return 0
  mkdir -p "$(dirname "$2")"
  cp -r "$1" "$2"
}

# write_once DEST CONTENT: copy_once for generated content.
write_once() {
  [[ -e "$1" ]] && return 0
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

# write_root FILE CONTENT: write a root-owned file, only touching it when the content changed.
write_root() {
  if sudo test -f "$1" && [[ "$(sudo cat "$1")" == "$2" ]]; then return 0; fi
  sudo mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" | sudo tee "$1" >/dev/null
}

# fedora_version_ok OS_RELEASE_FILE -> status 0 when it describes Fedora 44 or newer.
fedora_version_ok() {
  local id version
  # shellcheck source=/dev/null
  id=$(. "$1" && echo "${ID:-}")
  # shellcheck source=/dev/null
  version=$(. "$1" && echo "${VERSION_ID:-0}")
  [[ "$id" == fedora && "$version" =~ ^[0-9]+$ ]] && ((version >= 44))
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: every line `ok`, then `all passed`.

- [ ] **Step 6: Write install.sh**

```bash
#!/usr/bin/env bash
# fedora-hyprland: turns a fresh Fedora 44 Minimal install into a Hyprland + Noctalia v5 desktop.
# Usage: ./install.sh   (as your normal user; re-running is safe and is how updates are applied)
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"
for lib in "$REPO_DIR"/lib/*.sh; do
  [[ "$lib" == */common.sh ]] && continue
  # shellcheck source=/dev/null
  source "$lib"
done

preflight() {
  [[ $EUID -ne 0 ]] || die "Run this as your normal user, not with sudo. It asks for your password when it needs it."
  fedora_version_ok /etc/os-release || die "This installer needs Fedora 44 or newer."
  curl -fsI --max-time 15 https://fedoraproject.org >/dev/null || die "No internet connection. Connect with nmtui, then run it again."
  sudo -v
  # Keep sudo's timestamp fresh for the whole run.
  while sleep 50; do sudo -n true; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
}

main() {
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'warn "Stopped at line $LINENO. Full log: $LOG_FILE. Fix the problem and run ./install.sh again; finished steps are skipped."' ERR
  preflight
  log "Done. Reboot to start Hyprland: systemctl reboot"
}

main "$@"
```

Run: `chmod +x install.sh && git update-index --chmod=+x install.sh 2>/dev/null; bash -n install.sh && echo syntax-ok`
Expected: `syntax-ok`

- [ ] **Step 7: Add LICENSE and CI**

`LICENSE`: the standard MIT license text with `Copyright (c) 2026 Finoo125`.

`.shellcheckrc` (the lib files share variables such as `REPO_DIR` and `DNF_NVIDIA`; checked one file at a time,
shellcheck would report them as unused or unassigned):
```
external-sources=true
disable=SC2034,SC2154
```

`.github/workflows/ci.yml`:
```yaml
name: ci
on: [push, pull_request]
jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install tools
        run: sudo apt-get update && sudo apt-get install -y shellcheck lua5.4
      - name: shellcheck
        run: shellcheck install.sh lib/*.sh tests/*.sh
      - name: bash unit tests
        run: bash tests/run.sh
```

- [ ] **Step 8: Commit**

```bash
git add lib/common.sh install.sh tests/ .github/ .shellcheckrc LICENSE
git commit -m "Add installer skeleton, shared helpers, test harness and CI"
```

---

### Task 2: Package sources and package lists

**Files:**
- Create: `lib/packages.sh`, `tests/test_packages.sh`, `tests/repoquery.sh`
- Modify: `install.sh` (`main()`), `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `write_root`, `log` (Task 1).
- Produces: arrays `DNF_BASE DNF_DESKTOP DNF_APPS DNF_CLI DNF_MEDIA DNF_GAMING DNF_SYSTEM DNF_DEV DNF_NVIDIA DNF_SECUREBOOT FLATPAKS`; `all_dnf_packages` (one name per line); `terra_extra_repos` (stdin: `dnf repo list --all` output → Terra repo ids to disable); `setup_repos`; `install_packages`; `install_flatpaks`. Task 7 uses `DNF_NVIDIA` and `DNF_SECUREBOOT`.

- [ ] **Step 1: Write the failing test**

`tests/test_packages.sh`:
```bash
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
assert_eq "$(sort <<<"$all" | uniq -d)" "" "no package is listed twice"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_packages.sh`
Expected: FAIL, `lib/packages.sh: No such file or directory`.

- [ ] **Step 3: Implement lib/packages.sh**

```bash
# shellcheck shell=bash
# Package sources and package lists. Every function here is safe to run again.

COPR_REPO="lionheartp/Hyprland"
TERRA_ALLOW="noctalia-greeter*,ghostty*,bibata-cursor-theme*"
VSCODE_REPO='[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc'

DNF_BASE=(dnf5-plugins flatpak pciutils jq)
DNF_DESKTOP=(hyprland uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk noctalia greetd noctalia-greeter
  pipewire pipewire-pulseaudio wireplumber bluez NetworkManager-wifi nm-connection-editor tuned-ppd upower
  gnome-keyring ddcutil bolt polkit qt5-qtwayland qt6-qtwayland qt6ct nwg-look adw-gtk3-theme papirus-icon-theme
  bibata-cursor-theme xsettingsd google-noto-sans-fonts google-noto-color-emoji-fonts jetbrains-mono-fonts-all
  wl-clipboard grim slurp hyprpicker xdg-user-dirs xdg-utils)
DNF_APPS=(ghostty Thunar thunar-archive-plugin thunar-volman tumbler ffmpegthumbnailer gvfs gvfs-mtp gvfs-smb
  file-roller firefox mpv qview papers gnome-text-editor gnome-calculator gnome-software kde-connect)
DNF_CLI=(git wget2-wget curl fastfetch btop bat eza fzf ripgrep fd-find zoxide unzip 7zip bash-completion plocate)
DNF_MEDIA=(intel-media-driver libva-utils)
DNF_GAMING=(steam gamemode mangohud gamescope lutris protontricks winetricks vulkan-tools)
DNF_SYSTEM=(fuse-libs cups system-config-printer avahi nss-mdns fprintd fprintd-pam snapper btrfs-assistant
  libdnf5-plugin-actions fwupd)
DNF_DEV=(gcc make uv python3 python3.12 python3.13 nodejs24 nodejs24-npm podman distrobox code
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
DNF_NVIDIA=(akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-power
  libva-nvidia-driver switcheroo-control)
DNF_SECUREBOOT=(kmodtool akmods mokutil openssl)
FLATPAKS=(com.discordapp.Discord org.signal.Signal org.telegram.desktop com.rtosta.zapzap org.mozilla.Thunderbird
  org.videolan.VLC com.bitwarden.desktop md.obsidian.Obsidian io.dbeaver.DBeaverCommunity org.localsend.localsend_app
  com.vysp3r.ProtonPlus com.heroicgameslauncher.hgl io.github.Faugus.faugus-launcher it.mijorus.gearlever
  com.github.tchx84.Flatseal io.missioncenter.MissionCenter)

# all_dnf_packages -> every dnf package the installer may install, one per line (CI checks they exist).
all_dnf_packages() {
  printf '%s\n' "${DNF_BASE[@]}" "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_CLI[@]}" "${DNF_MEDIA[@]}" \
    "${DNF_GAMING[@]}" "${DNF_SYSTEM[@]}" "${DNF_DEV[@]}" "${DNF_NVIDIA[@]}" "${DNF_SECUREBOOT[@]}" ffmpeg
}

# terra_extra_repos: stdin = `dnf repo list --all` output -> Terra repo ids except the main "terra" repo.
terra_extra_repos() { awk '$1 ~ /^terra-/ {print $1}'; }

setup_repos() {
  local fedora repo
  fedora=$(rpm -E %fedora)
  sudo dnf install -y "${DNF_BASE[@]}"
  if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
    sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora}.noarch.rpm"
  fi
  sudo dnf copr enable -y "$COPR_REPO"
  if ! rpm -q terra-release >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # $releasever is expanded by dnf, not by the shell
    sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
  fi
  # Terra only provides the greeter, Ghostty and the Bibata cursor; nothing else from it may replace Fedora packages.
  sudo dnf config-manager setopt "terra.includepkgs=$TERRA_ALLOW"
  for repo in $(dnf repo list --all | terra_extra_repos); do
    sudo dnf config-manager setopt "$repo.enabled=0"
  done
  if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  write_root /etc/yum.repos.d/vscode.repo "$VSCODE_REPO"
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

install_packages() {
  sudo dnf install -y "${DNF_DESKTOP[@]}" "${DNF_APPS[@]}" "${DNF_CLI[@]}" "${DNF_SYSTEM[@]}" \
    "${DNF_GAMING[@]}" "${DNF_DEV[@]}"
  # RPM Fusion's full ffmpeg replaces Fedora's ffmpeg-free; the multimedia group adds the matching GStreamer plugins.
  sudo dnf install -y --allowerasing ffmpeg
  sudo dnf group install -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
  sudo dnf install -y "${DNF_MEDIA[@]}"
}

install_flatpaks() {
  sudo flatpak install -y --noninteractive flathub "${FLATPAKS[@]}"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_packages.sh`
Expected: all `ok`, `all passed`.

- [ ] **Step 5: Add the CI repoquery check**

`tests/repoquery.sh`:
```bash
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
available=$(dnf repoquery --available --qf '%{name}.%{arch}\n' "${wanted[@]}" 2>/dev/null)
missing=0
for p in "${wanted[@]}"; do
  if [[ "$p" == *.i686 ]]; then pattern="^${p//./\\.}$"; else pattern="^${p//./\\.}\\."; fi
  grep -qE "$pattern" <<<"$available" || { echo "missing dnf package: $p"; missing=1; }
done
for app in "${FLATPAKS[@]}"; do
  flatpak remote-info flathub "$app" >/dev/null 2>&1 || { echo "missing flatpak: $app"; missing=1; }
done
exit $missing
```

Append to `.github/workflows/ci.yml` under `jobs:`:
```yaml
  packages:
    runs-on: ubuntu-latest
    container: fedora:44
    steps:
      - uses: actions/checkout@v4
      - name: Every package and Flatpak exists
        run: bash tests/repoquery.sh
```

- [ ] **Step 6: Wire into install.sh**

In `main()` of `install.sh`, replace:
```bash
  preflight
  log "Done. Reboot to start Hyprland: systemctl reboot"
```
with:
```bash
  preflight
  log "Repositories";        setup_repos
  log "Packages";            install_packages
  log "Flatpak apps";        install_flatpaks
  log "Done. Reboot to start Hyprland: systemctl reboot"
```

Run: `bash tests/run.sh && bash -n install.sh && echo ok`
Expected: `all passed` for both test files, then `ok`.

- [ ] **Step 7: Commit**

```bash
git add lib/packages.sh tests/test_packages.sh tests/repoquery.sh install.sh .github/workflows/ci.yml
git commit -m "Add package sources, package lists and CI package check"
```

---

### Task 3: Apps outside dnf (JetBrains Toolbox, Claude Code, ArtCraft)

**Files:**
- Create: `lib/apps.sh`, `tests/test_apps.sh`, `tests/fixtures/sums/hello.AppImage`
- Modify: `install.sh` (`main()`)

**Interfaces:**
- Consumes: `have`, `warn` (Task 1).
- Produces: `ARTCRAFT_APPIMAGE` (path), `sha256_ok FILE SUMS_FILE`, `write_desktop_entry ID NAME EXEC ICON CATEGORIES`, `install_apps` (Toolbox + Claude Code), `install_artcraft` (called from the optional-steps prompt in Task 6).

- [ ] **Step 1: Write the failing test**

Create the fixture: `printf 'hello\n' > tests/fixtures/sums/hello.AppImage`

`tests/test_apps.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/apps.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
file=tests/fixtures/sums/hello.AppImage
good=$(sha256sum "$file" | cut -d' ' -f1)
printf '%s  hello.AppImage\n%s  other.deb\n' "$good" "0000" >"$tmp/good.txt"
printf '%s  hello.AppImage\n' "deadbeef" >"$tmp/bad.txt"
printf '%s  other.deb\n' "$good" >"$tmp/absent.txt"
assert_true  "matching checksum is accepted"       sha256_ok "$file" "$tmp/good.txt"
assert_false "wrong checksum is rejected"          sha256_ok "$file" "$tmp/bad.txt"
assert_false "file missing from SHA256SUMS fails"  sha256_ok "$file" "$tmp/absent.txt"

HOME="$tmp" write_desktop_entry demo "Demo App" "/opt/demo --flag" demo-icon "Graphics;"
entry=$(cat "$tmp/.local/share/applications/demo.desktop")
assert_true "desktop entry has Exec" grep -qx 'Exec=/opt/demo --flag' <<<"$entry"
assert_true "desktop entry has Name" grep -qx 'Name=Demo App' <<<"$entry"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_apps.sh`
Expected: FAIL, `lib/apps.sh: No such file or directory`.

- [ ] **Step 3: Implement lib/apps.sh**

```bash
# shellcheck shell=bash
# Apps that don't come from dnf or Flathub.

ARTCRAFT_REPO="storytold/craft-launcher" # official; github.com/craft-launcher/craft-launcher is a lookalike
ARTCRAFT_APPIMAGE="$HOME/Applications/ArtCraft-Launcher.AppImage"
TOOLBOX_DIR="$HOME/.local/share/JetBrains/Toolbox"

# sha256_ok FILE SUMS_FILE -> 0 when FILE's sha256 is listed for its basename in SUMS_FILE.
sha256_ok() {
  local want got
  want=$(awk -v n="$(basename "$1")" '$2 == n || $2 == "*"n {print $1}' "$2")
  [[ -n "$want" ]] || return 1
  got=$(sha256sum "$1" | cut -d' ' -f1)
  [[ "$got" == "$want" ]]
}

# write_desktop_entry ID NAME EXEC ICON CATEGORIES -> ~/.local/share/applications/ID.desktop
write_desktop_entry() {
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
Categories=$5
Terminal=false
EOF
}

install_jetbrains_toolbox() {
  local url tmp
  [[ -x "$TOOLBOX_DIR/bin/jetbrains-toolbox" ]] && return 0
  url=$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' |
    jq -r '.TBA[0].downloads.linux.link')
  tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1
  # Toolbox 2.x lives in ~/.local/share/JetBrains/Toolbox/bin and updates itself there.
  mkdir -p "$TOOLBOX_DIR"
  cp -r "$tmp"/. "$TOOLBOX_DIR"/
  rm -rf "$tmp"
  write_desktop_entry jetbrains-toolbox "JetBrains Toolbox" "$TOOLBOX_DIR/bin/jetbrains-toolbox" jetbrains-toolbox "Development;"
}

install_claude_code() {
  have claude && return 0
  [[ -x "$HOME/.local/bin/claude" ]] && return 0
  curl -fsSL https://claude.ai/install.sh | bash
}

install_apps() {
  install_jetbrains_toolbox
  install_claude_code
}

# install_artcraft: official AppImage, checksum-verified, never run as root.
install_artcraft() {
  local json app_url sums_url tmp name
  json=$(curl -fsSL "https://api.github.com/repos/$ARTCRAFT_REPO/releases/latest")
  app_url=$(jq -r '.assets[] | select(.name | test("linux-x86_64\\.AppImage$")) | .browser_download_url' <<<"$json")
  sums_url=$(jq -r '.assets[] | select(.name == "SHA256SUMS.txt") | .browser_download_url' <<<"$json")
  if [[ -z "$app_url" || -z "$sums_url" ]]; then warn "ArtCraft release has no Linux AppImage or checksums, skipped."; return 0; fi
  tmp=$(mktemp -d)
  name=$(basename "$app_url")
  curl -fsSL -o "$tmp/$name" "$app_url"
  curl -fsSL -o "$tmp/SHA256SUMS.txt" "$sums_url"
  if ! sha256_ok "$tmp/$name" "$tmp/SHA256SUMS.txt"; then
    warn "ArtCraft download failed its checksum check, so it was not installed."
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$ARTCRAFT_APPIMAGE")"
  install -m 755 "$tmp/$name" "$ARTCRAFT_APPIMAGE"
  rm -rf "$tmp"
  write_desktop_entry artcraft-launcher "ArtCraft Launcher" "$ARTCRAFT_APPIMAGE" applications-graphics "Graphics;"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_apps.sh`
Expected: all `ok`, `all passed`.

- [ ] **Step 5: Wire into install.sh**

In `main()`, after the `install_flatpaks` line add:
```bash
  log "Other apps";          install_apps
```

Run: `bash tests/run.sh && bash -n install.sh && echo ok` → Expected: `ok`.

- [ ] **Step 6: Commit**

```bash
git add lib/apps.sh tests/test_apps.sh tests/fixtures/sums install.sh
git commit -m "Add JetBrains Toolbox, Claude Code and checksum-verified ArtCraft install"
```

---

### Task 4: Hyprland defaults (Lua)

**Files:**
- Create: `config/hypr/main.lua`, `look.lua`, `input.lua`, `monitors.lua`, `desks.lua`, `rules.lua`, `binds.lua`, `autostart.lua`; `tests/test_hypr.lua`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing from bash. Hyprland API used: `hl.config`, `hl.bind(keys, dispatcher|function, opts?)`, `hl.dispatch`, `hl.dsp.*`, `hl.monitor`, `hl.workspace_rule`, `hl.window_rule`, `hl.layer_rule`, `hl.gesture`, `hl.on(event, fn)`, `hl.exec_cmd`, `hl.get_monitors({ all? })` (objects with `.name`, `.description`), `hl.get_windows()` (objects with `.address` = `"0x…"` string, `.workspace.id`), `hl.get_active_workspace()` (`.id`), `hl.get_config("cursor.zoom_factor")`.
- Produces: `main.lua` returns `function(repo_path)`; the user stub (Task 5) calls `require(REPO .. "/config/hypr/main.lua")(REPO)`. `monitors.lua` returns `{ is_external(name), internal_enabled(monitors), apply() }`. `desks.lua` returns `{ focus_order(n, portrait_connected), move_target(active_ws_id, n), strays(windows) }`.

- [ ] **Step 1: Write the failing Lua test**

`tests/test_hypr.lua`:
```lua
-- Unit tests for the logic in config/hypr. Run from the repo root: lua tests/test_hypr.lua
local failures = 0
local function check(cond, msg)
  if cond then print("ok   " .. msg) else print("FAIL " .. msg); failures = failures + 1 end
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- Recording stub for Hyprland's `hl` table.
local state = { active = {}, all = {}, windows = {}, ws = { id = 1 } }
local calls = { binds = {}, monitors = {}, rules = {}, events = {}, dispatched = {} }
local function proxy(path)
  return setmetatable({}, {
    __index = function(_, k) return proxy(path .. "." .. k) end,
    __call = function(_, args) return { dsp = path, args = args } end,
  })
end
hl = {
  dsp = proxy("dsp"),
  bind = function(keys, action) calls.binds[keys] = action end,
  dispatch = function(d) table.insert(calls.dispatched, d) end,
  monitor = function(spec) table.insert(calls.monitors, spec) end,
  workspace_rule = function(spec) table.insert(calls.rules, spec) end,
  on = function(ev, fn) calls.events[ev] = calls.events[ev] or {}; table.insert(calls.events[ev], fn) end,
  get_monitors = function(opts) if opts and opts.all then return state.all end return state.active end,
  get_windows = function() return state.windows end,
  get_active_workspace = function() return state.ws end,
  get_config = function() return 1.0 end,
  config = function() end, window_rule = function() end, layer_rule = function() end,
  gesture = function() end, env = function() end, exec_cmd = function() end,
}

-- monitors.lua
local mon = dofile("config/hypr/monitors.lua")
check(mon.is_external("DP-5"), "DP-5 is external")
check(not mon.is_external("eDP-1"), "eDP-1 is the laptop panel")
check(not mon.is_external("FALLBACK"), "Hyprland's FALLBACK output is not a real monitor")
check(mon.internal_enabled({ { name = "eDP-1" } }), "undocked: panel on")
check(not mon.internal_enabled({ { name = "eDP-1" }, { name = "DP-5" } }), "docked: panel off")
check(mon.internal_enabled({ { name = "FALLBACK" } }), "last external unplugged: panel comes back")
check(mon.internal_enabled({}), "no monitors at all: panel on")

state.active = { { name = "DP-5", description = "HP Inc. HP X27i CNK0420XTM" } }
state.all = { { name = "eDP-1", description = "BOE 0x0BCA" }, state.active[1] }
calls.monitors = {}
mon.apply()
check(calls.monitors[1].output == "eDP-1" and calls.monitors[1].disabled == true, "docked: apply() disables eDP-1")
state.active = { { name = "FALLBACK", description = "" } }
calls.monitors = {}
mon.apply()
check(calls.monitors[1].output == "eDP-1" and not calls.monitors[1].disabled, "undocked: apply() enables eDP-1")
check(calls.events["monitor.added"] and calls.events["monitor.removed"], "dock handling runs on hotplug events")

-- desks.lua
local desks = dofile("config/hypr/desks.lua")
check(same(desks.focus_order(2, true), { 12, 2 }), "docked desk 2: portrait 12 first, main 2 last (focus ends on main)")
check(same(desks.focus_order(2, false), { 2 }), "undocked desk 2: only workspace 2")
check(desks.move_target(13, 1) == 11, "window on the portrait monitor moves to portrait desk 1")
check(desks.move_target(3, 4) == 4, "window on the main monitor moves to main desk 4")
local strays = desks.strays({
  { address = "0xa", workspace = { id = 12 } },
  { address = "0xb", workspace = { id = 2 } },
  { address = "0xc", workspace = { id = -98 } },
})
check(#strays == 1 and strays[1].address == "0xa" and strays[1].workspace == 2, "undock moves only portrait-desk windows")

state.active = { { name = "DP-6", description = "HP Inc. HP E27q G5 CNC42511SG" }, { name = "DP-5", description = "HP Inc. HP X27i" } }
calls.dispatched = {}
calls.binds["SUPER + code:11"]()
check(#calls.dispatched == 2 and calls.dispatched[1].args.workspace == "12" and calls.dispatched[2].args.workspace == "2",
  "Super+2 switches portrait to 12, then main to 2")

local rule_for_11
for _, r in ipairs(calls.rules) do if r.workspace == "11" then rule_for_11 = r end end
check(rule_for_11 and rule_for_11.layout_opts.orientation == "top", "portrait desks stack windows top/bottom")

-- binds.lua and main.lua load and register what they promise
dofile("config/hypr/binds.lua")
check(calls.binds["SUPER + Return"] ~= nil, "Super+Return is bound")
check(calls.binds["SUPER + code:11"] ~= nil and calls.binds["SUPER + ALT + code:11"] ~= nil, "desk and monitor-focus keys don't collide")

local loaded = {}
local real_require = require
require = function(p) table.insert(loaded, p); return {} end
dofile("config/hypr/main.lua")("/repo")
require = real_require
check(#loaded == 7 and loaded[1] == "/repo/config/hypr/look.lua", "main.lua loads all 7 modules by absolute path")

if failures > 0 then print(failures .. " failed"); os.exit(1) end
print("all passed")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `lua tests/test_hypr.lua` (install Lua first if needed: Fedora `sudo dnf install lua`, Ubuntu `sudo apt install lua5.4`, Windows `winget install DEVCOM.Lua`)
Expected: FAIL, `cannot open config/hypr/monitors.lua`.

- [ ] **Step 3: Implement the modules**

`config/hypr/main.lua`:
```lua
-- fedora-hyprland defaults. Your ~/.config/hypr/hyprland.lua calls this with the repo path.
-- Each module is a separate require, so an error in one doesn't stop the others.
return function(repo)
  local dir = repo .. "/config/hypr/"
  for _, name in ipairs({ "look", "input", "monitors", "desks", "rules", "binds", "autostart" }) do
    require(dir .. name .. ".lua")
  end
end
```

`config/hypr/look.lua`:
```lua
-- Layout and decoration. Border colors come from Noctalia's hyprland template (noctalia.lua).
hl.config({
  general = { gaps_in = 5, gaps_out = 10, border_size = 2, layout = "master" },
  -- Main screen and laptop: one window left, the rest stacked on the right.
  master = { orientation = "left", new_status = "slave", mfact = 0.5 },
  decoration = {
    rounding = 14,
    rounding_power = 2,
    shadow = { enabled = true, range = 4, render_power = 3, color = 0xee1a1a1a },
    blur = { enabled = true, size = 3, passes = 2, vibrancy = 0.1696 },
  },
  misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
})
```

`config/hypr/input.lua`:
```lua
-- Input. The keyboard layout is set in your ~/.config/hypr/hyprland.lua (taken from the Fedora installer).
hl.config({
  input = {
    follow_mouse = 1,
    touchpad = { natural_scroll = true },
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

`config/hypr/monitors.lua`:
```lua
-- Dock layout: HP E27q G5 portrait on the left, HP X27i on the right (top-aligned, like on Windows).
-- Monitors are matched by model, so port names (which differ per laptop and dock) don't matter.
local M = {}

hl.monitor({ output = "desc:HP Inc. HP E27q G5", mode = "preferred", position = "0x0", scale = 1, transform = 3 }) -- upside down? use 1
hl.monitor({ output = "desc:HP Inc. HP X27i", mode = "highrr", position = "1440x0", scale = 1 }) -- 144 Hz if the dock allows
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" }) -- anything else

-- FALLBACK/HEADLESS are outputs Hyprland creates itself when nothing is connected.
function M.is_external(name)
  return not (name:match("^eDP") or name:match("^FALLBACK") or name:match("^HEADLESS"))
end

-- The laptop panel is on only while no external monitor is connected.
function M.internal_enabled(monitors)
  for _, m in ipairs(monitors) do
    if M.is_external(m.name) then return false end
  end
  return true
end

function M.apply()
  local on = M.internal_enabled(hl.get_monitors())
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if m.name:match("^eDP") then
      if on then
        hl.monitor({ output = m.name, mode = "preferred", position = "auto", scale = "auto" })
      else
        hl.monitor({ output = m.name, disabled = true })
      end
    end
  end
end

-- Event driven: runs the moment a monitor is plugged in or out.
hl.on("hyprland.start", M.apply)
hl.on("monitor.added", M.apply)
hl.on("monitor.removed", M.apply)

return M
```

`config/hypr/desks.lua`:
```lua
-- Four linked desks: Super+N shows workspace N on the main monitor and 10+N on the portrait monitor.
-- Super+Shift+N moves the focused window to desk N on the monitor it's on.
local M = {}
local MAIN = "desc:HP Inc. HP X27i"
local PORTRAIT = "desc:HP Inc. HP E27q G5"
local PORTRAIT_MODEL = "HP E27q G5"

-- Workspaces to focus for desk n, in order; the last one keeps the focus.
function M.focus_order(n, portrait_connected)
  if portrait_connected then return { 10 + n, n } end
  return { n }
end

-- Portrait desks are workspaces 11-14.
function M.move_target(active_ws_id, n)
  if active_ws_id > 10 then return 10 + n end
  return n
end

-- After undocking, windows on 11-14 move to 1-4 so nothing is stranded.
function M.strays(windows)
  local out = {}
  for _, w in ipairs(windows) do
    local id = w.workspace and w.workspace.id
    if id and id >= 11 and id <= 14 then table.insert(out, { address = w.address, workspace = id - 10 }) end
  end
  return out
end

local function portrait_connected()
  for _, m in ipairs(hl.get_monitors()) do
    if m.description and m.description:find(PORTRAIT_MODEL, 1, true) then return true end
  end
  return false
end

for n = 1, 4 do
  hl.workspace_rule({ workspace = tostring(n), monitor = MAIN, default = (n == 1) })
  hl.workspace_rule({ workspace = tostring(10 + n), monitor = PORTRAIT, default = (n == 1), layout_opts = { orientation = "top" } })
  local key = "code:" .. (9 + n) -- digit keys by keycode (1 = code:10), works on QWERTZ and AZERTY
  hl.bind("SUPER + " .. key, function()
    for _, ws in ipairs(M.focus_order(n, portrait_connected())) do
      hl.dispatch(hl.dsp.focus({ workspace = tostring(ws) }))
    end
  end)
  hl.bind("SUPER + SHIFT + " .. key, function()
    local ws = hl.get_active_workspace()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(M.move_target(ws and ws.id or 1, n)), follow = false }))
  end)
end

hl.on("monitor.removed", function()
  if portrait_connected() then return end
  for _, s in ipairs(M.strays(hl.get_windows())) do
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. s.address, workspace = tostring(s.workspace), follow = false }))
  end
end)

return M
```

`config/hypr/rules.lua`:
```lua
-- Window and layer rules.
hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ name = "noctalia-settings", match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1080, 920 } })
hl.window_rule({
  name = "small-tools-float",
  match = { class = "^(org.gnome.Calculator|nm-connection-editor|system-config-printer)$" },
  float = true,
})
hl.layer_rule({
  name = "noctalia",
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})
```

`config/hypr/binds.lua`:
```lua
-- Keybinds: the CachyOS cachyos-hypr-noctalia set, written fresh. Desk keys (Super+1..4) are in desks.lua.
local mod = "SUPER"
local PORTRAIT = "desc:HP Inc. HP E27q G5"
local MAIN = "desc:HP Inc. HP X27i"
local function run(cmd) return hl.dsp.exec_cmd("uwsm app -- " .. cmd) end
local function noctalia(cmd) return hl.dsp.exec_cmd("noctalia msg " .. cmd) end

-- Windows
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + D", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + J", hl.dsp.layout("swapwithmaster"))
for key, dir in pairs({ Left = "left", Right = "right", Up = "up", Down = "down" }) do
  hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }))
end
for key, dir in pairs({ Left = "l", Right = "r", Up = "u", Down = "d" }) do
  hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind(mod .. " + Tab", noctalia("window-switcher"))
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize())
hl.bind(mod .. " + ALT + code:10", hl.dsp.focus({ monitor = PORTRAIT }))
hl.bind(mod .. " + ALT + code:11", hl.dsp.focus({ monitor = MAIN }))
hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("scratchpad"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratchpad" }))

local function zoom(delta)
  local z = hl.get_config("cursor.zoom_factor") + delta
  hl.config({ cursor = { zoom_factor = math.max(1.0, math.min(3.0, z)) } })
end
hl.bind(mod .. " + Minus", function() zoom(-0.3) end, { repeating = true })
hl.bind(mod .. " + Plus", function() zoom(0.3) end, { repeating = true })

-- Apps
hl.bind(mod .. " + Return", run("ghostty"))
hl.bind(mod .. " + E", run("thunar"))
hl.bind(mod .. " + W", run("firefox"))
hl.bind(mod .. " + T", run("gnome-text-editor --new-window"))
hl.bind(mod .. " + C", run("gnome-calculator"))
hl.bind("XF86Calculator", run("gnome-calculator"))
hl.bind("CONTROL + SHIFT + Escape", run("ghostty -e btop"))

-- Noctalia
hl.bind(mod .. " + Space", noctalia("panel-toggle launcher"))
hl.bind(mod .. " + period", noctalia("panel-toggle launcher /emo"))
hl.bind(mod .. " + X", noctalia("panel-toggle control-center"))
hl.bind(mod .. " + Z", noctalia("settings-toggle"))
hl.bind(mod .. " + A", noctalia("panel-toggle control-center notifications"))
hl.bind(mod .. " + V", noctalia("panel-toggle clipboard"))
hl.bind(mod .. " + L", noctalia("session lock"))
hl.bind(mod .. " + ALT + C", noctalia("panel-toggle session"))
hl.bind(mod .. " + SHIFT + W", noctalia("panel-toggle wallpaper"))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("hyprpicker -a -n"))
hl.bind("Print", noctalia("screenshot-region"))
hl.bind(mod .. " + Print", noctalia("screenshot-fullscreen"))

-- Hardware keys (also work on the lock screen)
local held, locked = { locked = true, repeating = true }, { locked = true }
hl.bind("XF86AudioRaiseVolume", noctalia("volume-up"), held)
hl.bind("XF86AudioLowerVolume", noctalia("volume-down"), held)
hl.bind("XF86AudioMute", noctalia("volume-mute"), locked)
hl.bind("XF86AudioMicMute", noctalia("mic-mute"), locked)
hl.bind("XF86AudioPlay", noctalia("media toggle"), locked)
hl.bind("XF86AudioPause", noctalia("media toggle"), locked)
hl.bind("XF86AudioNext", noctalia("media next"), locked)
hl.bind("XF86AudioPrev", noctalia("media previous"), locked)
hl.bind("XF86MonBrightnessUp", noctalia("brightness-up"), held)
hl.bind("XF86MonBrightnessDown", noctalia("brightness-down"), held)
```

`config/hypr/autostart.lua`:
```lua
-- Started once with Hyprland. uwsm runs your XDG autostart entries on its own.
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
  hl.exec_cmd("uwsm app -- gnome-software --gapplication-service") -- update notifications
end)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `lua tests/test_hypr.lua`
Expected: every line `ok`, `all passed`.

- [ ] **Step 5: Add Lua checks to CI**

Append to the `lint-and-test` job steps in `.github/workflows/ci.yml`:
```yaml
      - name: Lua syntax
        run: for f in config/hypr/*.lua; do luac5.4 -p "$f"; done
      - name: Lua unit tests
        run: lua5.4 tests/test_hypr.lua
```

- [ ] **Step 6: Commit**

```bash
git add config/hypr tests/test_hypr.lua .github/workflows/ci.yml
git commit -m "Add Hyprland Lua defaults: dock handling, linked desks, CachyOS keybinds"
```

---

### Task 5: User configuration (layering, Hyprland stub, Noctalia, wallpapers, GTK/Qt)

**Files:**
- Create: `lib/user.sh`, `tests/test_user.sh`, `config/noctalia/00-fedora-hyprland.toml`, `config/ghostty/config`, `config/uwsm/env`, `config/gtk-3.0/settings.ini`, `config/gtk-4.0/settings.ini`, `config/mimeapps.list`, `config/wallpapers.txt`
- Modify: `install.sh` (`main()`)

**Interfaces:**
- Consumes: `copy_once`, `write_once`, `warn`, `REPO_DIR` (Task 1).
- Produces: `WALL_DIR`; `kb_from_localectl TEXT` → `layout|variant`; `hypr_stub REPO LAYOUT VARIANT`; `noctalia_local_toml WALLPAPER`; `qt6ct_conf HOME`; `wallpaper_urls LIST`; `download_wallpapers LIST DIR`; `default_wallpaper LIST DIR`; `setup_user`. Task 6 uses `kb_from_localectl`, `default_wallpaper`, `WALL_DIR`.

- [ ] **Step 1: Write the failing test**

`tests/test_user.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/user.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

full='   System Locale: LANG=de_DE.UTF-8
       VC Keymap: de-nodeadkeys
      X11 Layout: de
     X11 Variant: nodeadkeys'
console_only='   System Locale: LANG=de_DE.UTF-8
       VC Keymap: de-nodeadkeys
      X11 Layout: (unset)'
layout_only='      X11 Layout: us'
nothing='   System Locale: LANG=C.UTF-8
       VC Keymap: (unset)'
assert_eq "de|nodeadkeys" "$(kb_from_localectl "$full")"         "X11 layout and variant are used"
assert_eq "de|nodeadkeys" "$(kb_from_localectl "$console_only")" "console keymap is used when X11 is unset"
assert_eq "us|"           "$(kb_from_localectl "$layout_only")"  "layout without variant"
assert_eq "us|"           "$(kb_from_localectl "$nothing")"      "falls back to us"

stub=$(hypr_stub /home/u/.local/share/fedora-hyprland de nodeadkeys)
assert_true "stub loads the repo defaults" grep -qF 'require("/home/u/.local/share/fedora-hyprland/config/hypr/main.lua")("/home/u/.local/share/fedora-hyprland")' <<<"$stub"
assert_true "stub sets the keyboard layout" grep -qF 'kb_layout = "de", kb_variant = "nodeadkeys"' <<<"$stub"
assert_true "stub loads gpu.lua only if present" grep -qF 'pcall(require, "gpu")' <<<"$stub"

printf '# comment\n\nhttps://example.org/a/one.jpg\nhttps://example.org/b/two.png\n' >"$tmp/list.txt"
assert_eq $'https://example.org/a/one.jpg\nhttps://example.org/b/two.png' "$(wallpaper_urls "$tmp/list.txt")" "comments and blank lines are skipped"
assert_eq "$tmp/walls/one.jpg" "$(default_wallpaper "$tmp/list.txt" "$tmp/walls")" "first entry is the default"

curl_calls=0
curl() { # fake: -o FILE URL; fails for two.png
  curl_calls=$((curl_calls + 1))
  local out url
  while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
  [[ "$url" == *two.png ]] && return 22
  echo data >"$out"
}
download_wallpapers "$tmp/list.txt" "$tmp/walls" 2>/dev/null
assert_true  "a working URL is downloaded"         test -f "$tmp/walls/one.jpg"
assert_false "a failing URL leaves no file"        test -e "$tmp/walls/two.png"
assert_false "a failing URL leaves no .part file"  test -e "$tmp/walls/two.png.part"
curl_calls=0
download_wallpapers "$tmp/list.txt" "$tmp/walls" 2>/dev/null
assert_eq "1" "$curl_calls" "re-run only retries what is missing"

assert_true "local toml sets the default wallpaper" grep -qF 'path = "/w/one.jpg"' <<<"$(noctalia_local_toml /w/one.jpg)"
assert_true "qt6ct uses Noctalia's colors" grep -qF 'color_scheme_path=/home/u/.config/qt6ct/colors/noctalia.conf' <<<"$(qt6ct_conf /home/u)"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_user.sh`
Expected: FAIL, `lib/user.sh: No such file or directory`.

- [ ] **Step 3: Implement lib/user.sh**

```bash
# shellcheck shell=bash
# Per-user configuration: config layering, Hyprland stub, wallpapers, GTK/Qt settings.

WALL_DIR="$HOME/Pictures/Wallpapers"

# kb_field NAME TEXT -> value of "NAME: value" in localectl output, empty if unset.
kb_field() { awk -F': *' -v k="$1" '$1 ~ k"$" && $2 != "(unset)" && $2 != "n/a" {print $2}' <<<"$2"; }

# kb_from_localectl TEXT -> "layout|variant" from `localectl status` (X11 first, then console keymap, then us).
kb_from_localectl() {
  local layout variant keymap
  layout=$(kb_field "X11 Layout" "$1")
  variant=$(kb_field "X11 Variant" "$1")
  if [[ -z "$layout" ]]; then
    keymap=$(kb_field "VC Keymap" "$1")
    layout=${keymap%%-*}
    if [[ "$keymap" == *-* ]]; then variant=${keymap#*-}; fi
  fi
  printf '%s|%s\n' "${layout:-us}" "$variant"
}

# hypr_stub REPO LAYOUT VARIANT -> ~/.config/hypr/hyprland.lua (written once, then it's yours).
hypr_stub() {
  cat <<EOF
-- Your Hyprland config. fedora-hyprland created it once and never overwrites it.
-- The defaults live in $1/config/hypr and update with the \`update\` command.
require("$1/config/hypr/main.lua")("$1")

-- GPU settings for this machine (install.sh writes gpu.lua when it sets up an NVIDIA driver).
pcall(require, "gpu")

-- Keyboard layout from the Fedora installer.
hl.config({ input = { kb_layout = "$2", kb_variant = "$3" } })

-- Your own changes go below this line.
EOF
}

# noctalia_local_toml WALLPAPER -> per-user values Noctalia needs as absolute paths.
noctalia_local_toml() {
  cat <<EOF
# Written by fedora-hyprland on every install.sh run. The Settings GUI overrides it.
[wallpaper.default]
path = "$1"
EOF
}

# qt6ct_conf HOME -> Qt apps use Noctalia's colors and Papirus icons.
qt6ct_conf() {
  cat <<EOF
[Appearance]
color_scheme_path=$1/.config/qt6ct/colors/noctalia.conf
custom_palette=true
icon_theme=Papirus-Dark
style=Fusion
EOF
}

wallpaper_urls() { grep -vE '^[[:space:]]*(#|$)' "$1"; }
default_wallpaper() { echo "$2/$(basename "$(wallpaper_urls "$1" | head -1)")"; }

# download_wallpapers LIST DIR: fetch missing wallpapers; a failed download warns and continues.
download_wallpapers() {
  local url file
  mkdir -p "$2"
  while read -r url; do
    file="$2/$(basename "$url")"
    [[ -f "$file" ]] && continue
    if curl -fsSL --retry 2 -o "$file.part" "$url"; then
      mv "$file.part" "$file"
    else
      rm -f "$file.part"
      warn "Could not download wallpaper $url"
    fi
  done < <(wallpaper_urls "$1")
}

set_desktop_settings() {
  dbus-run-session -- sh -c '
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
    gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Ice
    gsettings set org.gnome.desktop.interface cursor-size 24'
}

setup_user() {
  local kb item list="$REPO_DIR/config/wallpapers.txt"
  xdg-user-dirs-update
  mkdir -p "$HOME/.config/noctalia"
  ln -sfn "$REPO_DIR/config/noctalia/00-fedora-hyprland.toml" "$HOME/.config/noctalia/00-fedora-hyprland.toml"
  for item in ghostty/config uwsm/env gtk-3.0/settings.ini gtk-4.0/settings.ini mimeapps.list; do
    copy_once "$REPO_DIR/config/$item" "$HOME/.config/$item"
  done
  write_once "$HOME/.config/qt6ct/qt6ct.conf" "$(qt6ct_conf "$HOME")"
  kb=$(kb_from_localectl "$(localectl status)")
  write_once "$HOME/.config/hypr/hyprland.lua" "$(hypr_stub "$REPO_DIR" "${kb%%|*}" "${kb#*|}")"
  download_wallpapers "$list" "$WALL_DIR"
  noctalia_local_toml "$(default_wallpaper "$list" "$WALL_DIR")" >"$HOME/.config/noctalia/10-fedora-hyprland-local.toml"
  set_desktop_settings
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_user.sh`
Expected: all `ok`, `all passed`.

- [ ] **Step 5: Add the config files**

`config/noctalia/00-fedora-hyprland.toml`:
```toml
# fedora-hyprland defaults for Noctalia v5. Your own ~/.config/noctalia/*.toml files and the Settings GUI override these.

[theme]
mode    = "dark"
source  = "builtin"
builtin = "Ayu"

[theme.templates]
enable_builtin_templates = true
builtin_ids = ["gtk3", "gtk4", "qt", "ghostty", "btop", "hyprland"]

[wallpaper]
enabled   = true
fill_mode = "span"   # one image across both docked monitors; crop on a single screen

[idle.behavior.lock]
enabled = true
timeout = 600
action  = "lock"

[idle.behavior.screen-off]
enabled = true
timeout = 660
action  = "screen_off"

[idle.behavior.suspend]
enabled = true
timeout = 1800
action  = "lock_and_suspend"

[plugins]
enabled = ["icefish/phone-connect"]   # KDE Connect: battery, ring, SMS, clipboard for the Pixel
```

`config/ghostty/config`:
```
# fedora-hyprland default (created once; yours to edit). Noctalia's ghostty template adds the color theme.
font-family = JetBrains Mono
font-size = 11
window-padding-x = 10
window-padding-y = 10
confirm-close-surface = false
```

`config/uwsm/env`:
```sh
# Environment for the Hyprland session and every app it starts (read by uwsm).
export XCURSOR_THEME=Bibata-Modern-Ice
export XCURSOR_SIZE=24
export HYPRCURSOR_SIZE=24
export QT_QPA_PLATFORMTHEME=qt6ct
export ELECTRON_OZONE_PLATFORM_HINT=auto
export TERMINAL=ghostty
```

`config/gtk-3.0/settings.ini` and `config/gtk-4.0/settings.ini` (same content):
```ini
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Ice
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 11
gtk-application-prefer-dark-theme=1
```

`config/mimeapps.list` (desktop file names verified against Fedora 44 package file lists):
```ini
[Default Applications]
inode/directory=thunar.desktop
application/pdf=org.gnome.Papers.desktop
image/png=com.interversehq.qView.desktop
image/jpeg=com.interversehq.qView.desktop
image/webp=com.interversehq.qView.desktop
image/gif=com.interversehq.qView.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
video/webm=mpv.desktop
text/plain=org.gnome.TextEditor.desktop
text/html=org.mozilla.firefox.desktop
x-scheme-handler/http=org.mozilla.firefox.desktop
x-scheme-handler/https=org.mozilla.firefox.desktop
```

`config/wallpapers.txt` (first line = default; URLs pinned to commits, images are not stored in this repo):
```
# Wallpapers downloaded into ~/Pictures/Wallpapers. First entry is the default. Pinned to commits, so content can't change.
# Orbits (AngelJumbo/gruvbox-wallpapers)
https://raw.githubusercontent.com/AngelJumbo/gruvbox-wallpapers/293774acaa531ce106332f790c80301998066b25/wallpapers/mix/solar-system.jpg
# Mountain sigil (AngelJumbo/gruvbox-wallpapers)
https://raw.githubusercontent.com/AngelJumbo/gruvbox-wallpapers/293774acaa531ce106332f790c80301998066b25/wallpapers/minimalistic/gruv.jpg
# Event horizon (D3Ext/aesthetic-wallpapers)
https://raw.githubusercontent.com/D3Ext/aesthetic-wallpapers/e34f05935c5b768f4c016b0893924d18ec1dba61/images/planet_minimal.png
# Comet field (D3Ext/aesthetic-wallpapers)
https://raw.githubusercontent.com/D3Ext/aesthetic-wallpapers/e34f05935c5b768f4c016b0893924d18ec1dba61/images/colorful-planets.jpg
# Lotus glow (AngelJumbo/gruvbox-wallpapers)
https://raw.githubusercontent.com/AngelJumbo/gruvbox-wallpapers/293774acaa531ce106332f790c80301998066b25/wallpapers/photography/ameenfahmy-mXpTl4jNKiA.jpg
# Reaching light (dharmx/walls)
https://raw.githubusercontent.com/dharmx/walls/6bf4d733ebf2b484a37c17d742eb47e5139e6a14/unsorted/a_hand_reaching_out_to_the_sky.jpg
# Low sun (AngelJumbo/gruvbox-wallpapers)
https://raw.githubusercontent.com/AngelJumbo/gruvbox-wallpapers/293774acaa531ce106332f790c80301998066b25/wallpapers/minimalistic/sunset.png
# Moonwalk (vyrx-dev/Wallpapers)
https://raw.githubusercontent.com/vyrx-dev/Wallpapers/53e29b35fc242370e13f7dc1413ac8f5054e391e/others/astronaut2.png
# Comet night (JaKooLit/Wallpaper-Bank)
https://raw.githubusercontent.com/JaKooLit/Wallpaper-Bank/c5e1780c29adca428dc4ca2d970bd1a6a09f18f3/wallpapers/Comets-of-that-night.jpg
# Horizon sunset (JaKooLit/Wallpaper-Bank)
https://raw.githubusercontent.com/JaKooLit/Wallpaper-Bank/c5e1780c29adca428dc4ca2d970bd1a6a09f18f3/wallpapers/Sun-Setting-Horizon.png
```

Run: `for u in $(grep -v '^#' config/wallpapers.txt); do curl -fsI -o /dev/null -w '%{http_code} ' "$u"; done; echo`
Expected: `200` ten times.

- [ ] **Step 6: Wire into install.sh**

In `main()`, after the `install_apps` line add:
```bash
  log "Your configuration";  setup_user
```

Run: `bash tests/run.sh && bash -n install.sh && echo ok` → Expected: `ok`.

- [ ] **Step 7: Commit**

```bash
git add lib/user.sh tests/test_user.sh config/noctalia config/ghostty config/uwsm config/gtk-3.0 config/gtk-4.0 config/mimeapps.list config/wallpapers.txt install.sh
git commit -m "Add user config layering, Hyprland stub, Noctalia defaults and wallpapers"
```

---

### Task 6: System configuration (greeter, fingerprint, snapshots, icons, services) and optional steps

**Files:**
- Create: `lib/system.sh`, `tests/test_system.sh`, `config/snapper.actions`
- Modify: `install.sh` (`main()` + new `optional_steps`)

**Interfaces:**
- Consumes: `write_root`, `have`, `warn`, `ask_once` (Task 1); `kb_from_localectl`, `default_wallpaper`, `WALL_DIR` (Task 5); `install_artcraft`, `ARTCRAFT_APPIMAGE` (Task 3).
- Produces: `GREETER_DIR`; `greeter_session SESSIONS_DIR`; `greetd_config GREETER_CMD`; `greeter_toml LAYOUT VARIANT SESSION WALLPAPER`; `setup_system`; `optional_steps` (in install.sh).

- [ ] **Step 1: Write the failing test**

`tests/test_system.sh`:
```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_system.sh`
Expected: FAIL, `lib/system.sh: No such file or directory`.

- [ ] **Step 3: Implement lib/system.sh**

```bash
# shellcheck shell=bash
# System-wide configuration: login screen, fingerprint, snapshots, icons, services.

GREETER_DIR=/var/lib/noctalia-greeter
PAPIRUS_FOLDERS_SHA=0f838ee5679229e3a3e97e3b333c222c9e9615b4

# greeter_session SESSIONS_DIR -> session name for the greeter; prefers the uwsm-managed Hyprland session.
greeter_session() {
  if [[ -f "$1/hyprland-uwsm.desktop" ]]; then echo hyprland-uwsm; else echo hyprland; fi
}

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

# greeter_toml LAYOUT VARIANT SESSION WALLPAPER -> /var/lib/noctalia-greeter/greeter.toml
greeter_toml() {
  cat <<EOF
# Written by fedora-hyprland/install.sh on every run.
[session]
default = "$3"

[keyboard]
layout = "$1"
variant = "$2"

[appearance]
scheme = "Ayu"
theme_mode = "dark"
EOF
  if [[ -n "$4" ]]; then printf '\n[appearance.wallpaper]\npath = "%s"\nfill_mode = "crop"\n' "$4"; fi
}

setup_greeter() {
  local kb wall="" src
  kb=$(kb_from_localectl "$(localectl status)")
  write_root /etc/greetd/config.toml "$(greetd_config "$(command -v noctalia-greeter-session)")"
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
    "$(greeter_toml "${kb%%|*}" "${kb#*|}" "$(greeter_session /usr/share/wayland-sessions)" "$wall")"
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

setup_system() {
  setup_greeter
  setup_fingerprint
  setup_snapper
  setup_icons
  sudo systemctl enable --now bluetooth cups avahi-daemon tuned tuned-ppd fwupd-refresh.timer docker
  sudo usermod -aG docker "$USER"
  if systemctl is-active -q firewalld && ! sudo firewall-cmd --permanent --query-service=kdeconnect >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-service=kdeconnect
    sudo firewall-cmd --reload
  fi
}
```

`config/snapper.actions` (from the dnf5 actions plugin documentation, `man 8 libdnf5-actions`):
```
# Snapper pre/post snapshot around every dnf transaction (emulates the DNF4 snapper plugin).
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_descr=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -p\ -d\ '${tmp.snapper_descr}')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ "${tmp.snapper_descr}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.snapper_descr
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_system.sh`
Expected: all `ok`, `all passed`.

- [ ] **Step 5: Wire into install.sh with the optional steps**

Add this function to `install.sh` above `main()`:
```bash
# Questions asked at the end; a "no" is remembered so later runs (and `update`) don't ask again.
optional_steps() {
  local fp
  fp=$(fprintd-list "$USER" 2>&1 || true)
  if grep -q 'no fingers enrolled' <<<"$fp" && ask_once fingerprint "Enroll a fingerprint now (sudo, login, lock screen)?" y; then
    fprintd-enroll || warn "Fingerprint enrollment didn't finish. Run fprintd-enroll later."
  fi
  if [[ ! -f "$ARTCRAFT_APPIMAGE" ]] && ask_once artcraft "Install the ArtCraft Launcher (alpha creative apps)?" n; then
    install_artcraft
  fi
}
```

In `main()`, after the `setup_user` line add:
```bash
  log "System";              setup_system
  log "Optional steps";      optional_steps
```

Run: `bash tests/run.sh && bash -n install.sh && echo ok` → Expected: `ok`.

- [ ] **Step 6: Commit**

```bash
git add lib/system.sh tests/test_system.sh config/snapper.actions install.sh
git commit -m "Add greeter, fingerprint, snapshots, icons, services and optional steps"
```

---

### Task 7: Optional NVIDIA support (RTX 20 to RTX 50)

**Files:**
- Create: `lib/nvidia.sh`, `tests/test_nvidia.sh`
- Modify: `install.sh` (`main()`)

**Interfaces:**
- Consumes: `write_root`, `warn`, `die`, `have`, `ask_once`, `LOG_FILE` (Task 1); `DNF_NVIDIA`, `DNF_SECUREBOOT` (Task 2).
- Produces: `nvidia_classify LSPCI_DISPLAY_LINES` → `none|legacy|dedicated|hybrid` (input is `lspci -d ::03xx` output); `pci_slot LINES nvidia|other` → `0000:BB:DD.F`; `gpu_lua KIND`; `gpu_udev_rules IGPU_SLOT DGPU_SLOT`; `setup_nvidia` (honors `NVIDIA=yes|no`).

- [ ] **Step 1: Write the failing test**

`tests/test_nvidia.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh
source lib/common.sh
source lib/nvidia.sh

intel='00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics] (rev 0c)'
rtx20='01:00.0 VGA compatible controller: NVIDIA Corporation TU106 [GeForce RTX 2060 Rev. A] (rev a1)'
gtx16='01:00.0 VGA compatible controller: NVIDIA Corporation TU116 [GeForce GTX 1660 SUPER] (rev a1)'
rtx40='01:00.0 VGA compatible controller: NVIDIA Corporation AD104 [GeForce RTX 4070] (rev a1)'
rtx50='01:00.0 VGA compatible controller: NVIDIA Corporation GB205 [GeForce RTX 5070] (rev a1)'
gtx10='01:00.0 VGA compatible controller: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] (rev a1)'
hybrid=$'00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)\n01:00.0 3D controller: NVIDIA Corporation GA107M [GeForce RTX 3050 Mobile] (rev a1)'

assert_eq none      "$(nvidia_classify "$intel")"  "Intel-only laptop: nothing to do"
assert_eq dedicated "$(nvidia_classify "$rtx20")"  "RTX 20 (TU106) is supported"
assert_eq dedicated "$(nvidia_classify "$gtx16")"  "GTX 16 is Turing too (TU116)"
assert_eq dedicated "$(nvidia_classify "$rtx40")"  "RTX 40 (AD104) is supported"
assert_eq dedicated "$(nvidia_classify "$rtx50")"  "RTX 50 (GB205) is supported"
assert_eq legacy    "$(nvidia_classify "$gtx10")"  "GTX 10 (GP106) is reported as legacy"
assert_eq hybrid    "$(nvidia_classify "$hybrid")" "Intel + RTX 3050 laptop is hybrid"

assert_eq "0000:00:02.0" "$(pci_slot "$hybrid" other)"  "integrated GPU slot"
assert_eq "0000:01:00.0" "$(pci_slot "$hybrid" nvidia)" "NVIDIA GPU slot"

rules=$(gpu_udev_rules 0000:00:02.0 0000:01:00.0)
assert_true "udev rule for the iGPU symlink" grep -qF 'KERNEL=="card*", KERNELS=="0000:00:02.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/igpu"' <<<"$rules"
assert_true "udev rule for the dGPU symlink" grep -qF 'KERNELS=="0000:01:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/dgpu"' <<<"$rules"

assert_true  "hybrid renders on the iGPU"      grep -qF 'hl.env("AQ_DRM_DEVICES", "/dev/dri/igpu:/dev/dri/dgpu")' <<<"$(gpu_lua hybrid)"
assert_false "hybrid doesn't force GLX nvidia" grep -qF '__GLX_VENDOR_LIBRARY_NAME' <<<"$(gpu_lua hybrid)"
assert_true  "dedicated sets VA-API to nvidia" grep -qF 'hl.env("LIBVA_DRIVER_NAME", "nvidia")' <<<"$(gpu_lua dedicated)"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_nvidia.sh`
Expected: FAIL, `lib/nvidia.sh: No such file or directory`.

- [ ] **Step 3: Implement lib/nvidia.sh**

```bash
# shellcheck shell=bash
# Optional NVIDIA driver for RTX 20 to RTX 50 (Turing and newer), dedicated or hybrid.
# Follows RPM Fusion's NVIDIA, Secure Boot and Optimus HowTos.

NVIDIA_KEY=/etc/pki/akmods/certs/public_key.der
NVIDIA_RUN='#!/bin/sh
# Run a program on the NVIDIA GPU of a hybrid laptop. Steam launch option: nvidia-run %command%
export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only
exec "$@"'

# nvidia_classify LINES -> none | legacy | dedicated | hybrid. LINES = `lspci -d ::03xx` (display controllers only).
nvidia_classify() {
  local nv others
  nv=$(grep -i 'nvidia' <<<"$1" || true)
  others=$(grep -vi 'nvidia' <<<"$1" | grep -v '^[[:space:]]*$' || true)
  if [[ -z "$nv" ]]; then
    echo none
  elif ! grep -qE '\b(TU1|GA1|AD1|GB2)[0-9]{2}' <<<"$nv"; then
    echo legacy # GTX 10 and older need RPM Fusion's 580xx legacy driver
  elif [[ -n "$others" ]]; then
    echo hybrid
  else
    echo dedicated
  fi
}

# pci_slot LINES nvidia|other -> PCI address of the first matching GPU, e.g. 0000:01:00.0
pci_slot() {
  local line
  if [[ "$2" == nvidia ]]; then
    line=$(grep -i nvidia <<<"$1" | head -1)
  else
    line=$(grep -vi nvidia <<<"$1" | grep -v '^[[:space:]]*$' | head -1)
  fi
  echo "0000:${line%% *}"
}

# gpu_udev_rules IGPU DGPU -> stable /dev/dri/igpu and /dev/dri/dgpu (cardN numbers change between boots).
gpu_udev_rules() {
  printf 'KERNEL=="card*", KERNELS=="%s", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/igpu"\n' "$1"
  printf 'KERNEL=="card*", KERNELS=="%s", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/dgpu"\n' "$2"
}

# gpu_lua KIND -> ~/.config/hypr/gpu.lua for this machine.
gpu_lua() {
  echo "-- Written by fedora-hyprland/install.sh for this machine's NVIDIA GPU ($1). Regenerated on every run."
  if [[ "$1" == hybrid ]]; then
    echo '-- Render on the integrated GPU to save battery; start an app on the NVIDIA GPU with: nvidia-run <app>'
    echo 'hl.env("AQ_DRM_DEVICES", "/dev/dri/igpu:/dev/dri/dgpu")'
  else
    echo 'hl.env("LIBVA_DRIVER_NAME", "nvidia")'
    echo 'hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")'
    echo 'hl.env("NVD_BACKEND", "direct")'
  fi
}

# Secure Boot: the module must be signed with our key, so the key is created and queued before the driver builds.
nvidia_secure_boot() {
  have mokutil || sudo dnf install -y mokutil
  mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled' || return 0
  sudo dnf install -y "${DNF_SECUREBOOT[@]}"
  sudo test -f "$NVIDIA_KEY" || sudo kmodgenca -a
  if mokutil --test-key "$NVIDIA_KEY" 2>/dev/null | grep -q 'already enrolled'; then return 0; fi
  cat <<'EOF'

Secure Boot is on, so the NVIDIA driver has to be signed with your own key.
Choose a one-time password now. After the reboot a blue "MOK management" screen appears:
  Enroll MOK -> Continue -> Yes -> type the password -> Reboot
That screen always uses a US keyboard layout. Use only letters a-x and digits (no y, z or symbols).

EOF
  sudo mokutil --import "$NVIDIA_KEY"
}

# Build the module now (not in the background), so a reboot never lands on a missing driver.
nvidia_build() {
  sudo akmods --kernels "$(uname -r)"
  modinfo -F version nvidia >/dev/null 2>&1 ||
    die "The NVIDIA kernel module didn't build. Don't reboot yet: check $LOG_FILE and https://rpmfusion.org/Howto/NVIDIA"
}

nvidia_hybrid() {
  write_root /etc/udev/rules.d/61-fedora-hyprland-gpu.rules "$(gpu_udev_rules "$(pci_slot "$1" other)" "$(pci_slot "$1" nvidia)")"
  write_root /etc/modprobe.d/fedora-hyprland-nvidia.conf 'options nvidia NVreg_DynamicPowerManagement=0x02'
  write_root /usr/local/bin/nvidia-run "$NVIDIA_RUN"
  sudo chmod 755 /usr/local/bin/nvidia-run
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=drm
  sudo systemctl enable switcheroo-control
}

setup_nvidia() {
  local gpus kind
  gpus=$(lspci -d ::03xx)
  kind=$(nvidia_classify "$gpus")
  case "$kind" in
    none) return 0 ;;
    legacy)
      warn "This NVIDIA GPU is older than RTX 20 (Turing) and isn't supported by this installer. See https://rpmfusion.org/Howto/NVIDIA (580xx legacy driver)."
      return 0
      ;;
  esac
  if ! rpm -q akmod-nvidia >/dev/null 2>&1; then
    if [[ "${NVIDIA:-}" == no ]]; then return 0; fi
    if [[ "${NVIDIA:-}" != yes ]] && ! ask_once nvidia "NVIDIA GPU found ($kind). Install the NVIDIA driver?" y; then return 0; fi
    nvidia_secure_boot
    sudo dnf install -y "${DNF_NVIDIA[@]}"
  fi
  nvidia_build
  sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate
  mkdir -p "$HOME/.config/hypr"
  gpu_lua "$kind" >"$HOME/.config/hypr/gpu.lua"
  if [[ "$kind" == hybrid ]]; then nvidia_hybrid "$gpus"; fi
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_nvidia.sh`
Expected: all `ok`, `all passed`.

- [ ] **Step 5: Wire into install.sh**

In `main()`, after the `setup_system` line add:
```bash
  log "NVIDIA";              setup_nvidia
```

Run: `bash tests/run.sh && bash -n install.sh && echo ok` → Expected: `ok`.

- [ ] **Step 6: Commit**

```bash
git add lib/nvidia.sh tests/test_nvidia.sh install.sh
git commit -m "Add optional NVIDIA support for RTX 20-50 (dedicated and hybrid, Secure Boot)"
```

---

### Task 8: The `update` command

**Files:**
- Create: `bin/update`
- Modify: `lib/common.sh` (add `newest_version`), `tests/test_common.sh`, `lib/user.sh` (`setup_user` links it), `.github/workflows/ci.yml` (shellcheck `bin/update`)

**Interfaces:**
- Consumes: `log`, `REPO_DIR` (Task 1); `install.sh`.
- Produces: `newest_version` (stdin: version strings → highest by `sort -V`); `~/.local/bin/update` → `bin/update`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_common.sh`, before `finish`:
```bash
kernels=$'6.19.8-300.fc44.x86_64\n7.0.2-200.fc44.x86_64\n6.19.10-300.fc44.x86_64'
assert_eq "7.0.2-200.fc44.x86_64" "$(newest_version <<<"$kernels")" "newest kernel wins by version, not by text"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_common.sh`
Expected: FAIL on the new line (`newest_version: command not found`).

- [ ] **Step 3: Implement**

Append to `lib/common.sh`:
```bash
# newest_version: stdin = version strings, one per line -> the highest one.
newest_version() { sort -V | tail -1; }
```

`bin/update`:
```bash
#!/usr/bin/env bash
# One command for all updates: system packages, NVIDIA module, Flatpaks, firmware and the fedora-hyprland defaults.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

log "System packages (snapper takes a snapshot before and after)"
sudo dnf upgrade --refresh -y

if rpm -q akmod-nvidia >/dev/null 2>&1; then
  log "NVIDIA module for the newest kernel"
  sudo akmods --kernels "$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | newest_version)"
fi

log "Flatpak apps"
sudo flatpak update -y --noninteractive

log "Firmware"
fwupdmgr refresh --force >/dev/null 2>&1 || true
fwupdmgr update -y || echo "No firmware updates."

log "fedora-hyprland defaults"
git -C "$REPO_DIR" pull --ff-only
"$REPO_DIR/install.sh"
```

Run: `chmod +x bin/update && git update-index --chmod=+x bin/update 2>/dev/null; bash -n bin/update && echo ok` → Expected: `ok`.

In `lib/user.sh`, at the end of `setup_user()` add:
```bash
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$REPO_DIR/bin/update" "$HOME/.local/bin/update"
```

In `.github/workflows/ci.yml`, change the shellcheck step to:
```yaml
        run: shellcheck install.sh bin/update lib/*.sh tests/*.sh
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `all passed` for every test file.

- [ ] **Step 5: Commit**

```bash
git add bin/update lib/common.sh lib/user.sh tests/test_common.sh .github/workflows/ci.yml
git commit -m "Add the update command"
```

---

### Task 9: README, publish, and the VM acceptance run

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write README.md**

Contents, in this order (plain, short sections):
1. **What it is:** one paragraph: Fedora 44 Minimal + Hyprland + Noctalia v5, CachyOS-style setup, stable Fedora base.
2. **Before you start:** Fedora 44 *Everything* netinstall ISO → "Minimal Install"; default automatic partitioning (btrfs) keeps snapshots working; connect to the network.
3. **Install:**
   ```bash
   sudo dnf install -y git
   git clone https://github.com/Finoo125/fedora-hyprland ~/.local/share/fedora-hyprland
   ~/.local/share/fedora-hyprland/install.sh
   systemctl reboot
   ```
4. **Update:** `update` (what it does, from `bin/update`).
5. **Keybinds:** the two tables from the spec (CachyOS set + desk keys).
6. **Monitors and docking:** the two HP models, how to adapt `desc:` names (`hyprctl monitors`), the `transform = 3`/`1` knob and where to override it in `~/.config/hypr/hyprland.lua`.
7. **Your own changes:** which files are yours (stub, ghostty, gtk, mimeapps, `~/.config/noctalia/*.toml`) and which are regenerated.
8. **NVIDIA (untested):** detection, Secure Boot MOK steps incl. the US-keyboard warning, `nvidia-run`, `NVIDIA=yes|no`.
9. **Recovery:** pick the previous kernel in GRUB; Btrfs Assistant → Snapper → restore the pre-update snapshot; switch to a TTY with Ctrl+Alt+F3.
10. **Credits:** CachyOS `cachyos-hypr-noctalia` (keybind set), Noctalia, `lionheartp/Hyprland` COPR, Terra; wallpapers: each source repo from `config/wallpapers.txt`, with the note that images are downloaded from their authors' repos and not redistributed here.
11. **License:** MIT (code and configs; wallpapers belong to their authors).

Run: `grep -c '' README.md` → Expected: a non-zero line count; read it once top to bottom for accuracy against the spec.

- [ ] **Step 2: Full local check**

Run: `bash tests/run.sh && lua tests/test_hypr.lua && bash -n install.sh bin/update && echo all-green`
Expected: `all passed` for every file, then `all-green`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README"
```

- [ ] **Step 4: Publish to GitHub (ask the user first: this creates a public repo)**

After the user confirms:
```bash
gh repo create Finoo125/fedora-hyprland --public --source . --remote origin --push \
  --description "Fedora 44 Minimal -> Hyprland + Noctalia v5 in one command"
gh run watch --exit-status "$(gh run list --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: both CI jobs green (`lint-and-test`, `packages`). A red `packages` job names the missing package or Flatpak: fix the name in `lib/packages.sh`, commit, push.

- [ ] **Step 5: VM acceptance run (the user runs this; report results back)**

On a Fedora 44 Minimal VM (Boxes/virt-manager/Hyper-V, 4 GB RAM, 40 GB disk, UEFI):
1. Install as above; the run ends with "Done".
2. Run `~/.local/share/fedora-hyprland/install.sh` again: no prompts, no errors, finishes in a few minutes.
3. Reboot: Noctalia Greeter appears with Ayu colors, the Orbits wallpaper and the right keyboard layout; log in to Hyprland.
4. Check: `Super+Return` opens Ghostty with Ayu colors; `Super+Space` launcher; `Super+1..4` switches desks; `Super+Shift+W` shows 10 wallpapers; `xdg-mime query default x-scheme-handler/https` prints `org.mozilla.firefox.desktop`; `node --version` works (if not, `nodejs24` doesn't provide `/usr/bin/node` and needs `nodejs24-bin`); `snapper list` shows pre/post pairs after any `sudo dnf install`.
5. Then the real laptops, including plugging and unplugging the dock: laptop panel off when docked, back on when undocked, X27i at 144 Hz (`hyprctl monitors`), portrait right side up.
