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
