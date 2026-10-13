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

# newest_version: stdin = version strings, one per line -> the highest one.
newest_version() { sort -V | tail -1; }
