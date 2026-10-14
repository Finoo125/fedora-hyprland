# shellcheck shell=bash
# Language, keyboard layout and timezone. The system (localectl/timedatectl) is the only place they are stored:
# Hyprland and the login screen read the keyboard from it, so `sudo localectl set-x11-keymap us` + `update` is enough.

XKB_CONF=/etc/X11/xorg.conf.d/00-keyboard.conf

# xkb_option CONF NAME -> value of Option "Xkb<NAME>" in localed's keyboard file, empty when missing.
xkb_option() {
  [[ -r "$1" ]] || return 0
  sed -n "s/^[[:space:]]*Option[[:space:]]*\"Xkb$2\"[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1
}

# keyboard_layout CONF -> the system's first keyboard layout, "us" when none is set.
keyboard_layout() {
  local layout
  layout=$(xkb_option "$1" Layout)
  layout="${layout%%,*}"
  echo "${layout:-us}"
}

# langpack_for LANG -> Fedora langpacks package for a locale: de_DE.UTF-8 -> langpacks-de, pt_BR.UTF-8 -> langpacks-pt_BR.
langpack_for() {
  local base="${1%%.*}"
  base="${base%%@*}"
  case "$base" in
    pt_BR | zh_CN | zh_TW | zh_HK) echo "langpacks-$base" ;;
    *) echo "langpacks-${base%%_*}" ;;
  esac
}

# ask_value QUESTION DEFAULT LIST_CMD... -> the answer (DEFAULT on Enter). Answers not in LIST_CMD's output are
# asked again; "none" is always accepted.
ask_value() {
  local question="$1" default="$2" reply
  shift 2
  while true; do
    read -r -p "$question [$default] " reply || { echo "$default"; return 0; }
    reply="${reply:-$default}"
    if [[ "$reply" == none ]] || "$@" 2>/dev/null | grep -qxF "$reply"; then echo "$reply"; return 0; fi
    warn "\"$reply\" isn't known. \`$*\` lists every choice."
  done
}

# Asked once, at the start; `update` keeps whatever the system has.
setup_locale() {
  local marker="$STATE_DIR/locale-chosen" lang layout variant tz
  # shellcheck source=/dev/null
  lang=$(. /etc/locale.conf 2>/dev/null; echo "${LANG:-C.UTF-8}")
  layout=$(xkb_option "$XKB_CONF" Layout)
  variant=$(xkb_option "$XKB_CONF" Variant)
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)
  if [[ ! -f "$marker" && -z "${ASSUME:-}" ]]; then
    printf 'Language: %s   Keyboard: %s%s   Timezone: %s\n' "$lang" "${layout:-us}" "${variant:+ ($variant)}" "$tz"
    if ! ask "Keep these?" y; then
      lang=$(ask_value "Language (e.g. en_US.UTF-8, de_DE.UTF-8)?" "$lang" localectl list-locales)
      layout=$(ask_value "Keyboard layout (e.g. us, de, fr, gb)?" "${layout:-us}" localectl list-x11-keymap-layouts)
      # Variants belong to a layout; Enter on "none" means the layout's default.
      variant=$(ask_value "Keyboard variant (e.g. nodeadkeys, intl; none for the default)?" "${variant:-none}" \
        localectl list-x11-keymap-variants "$layout")
      [[ "$variant" == none ]] && variant=""
      tz=$(ask_value "Timezone (e.g. Europe/Berlin, America/New_York)?" "$tz" timedatectl list-timezones)
      sudo localectl set-locale "LANG=$lang"
      sudo localectl set-x11-keymap "$layout" "" "$variant"
      sudo timedatectl set-timezone "$tz"
    fi
    mkdir -p "$STATE_DIR"
    : >"$marker"
  fi
  # Translations for the chosen language (apps, spell checking, fonts); English needs none beyond the default.
  if [[ "$lang" != C.* && "$lang" != C && "$lang" != POSIX ]]; then
    sudo dnf install -y "$(langpack_for "$lang")" || warn "No language pack for $lang; apps may stay in English."
  fi
}
