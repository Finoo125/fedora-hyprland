#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source tests/lib.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
presets=(config/noctalia/presets/*.toml)
assert_true "the looks ship as presets" test ${#presets[@]} -ge 1
for f in "${presets[@]}"; do
  name=$(basename "$f" .toml)
  assert_true "$name is valid TOML" python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$f"
  assert_true "$name says what it is" grep -q "^# Preset \"$name\": " "$f"
  wall=$(sed -n 's|^# wallpaper = ~/Pictures/Wallpapers/||p' "$f")
  assert_true "$name's wallpaper is downloaded by the installer" grep -q "/$wall\$" config/wallpapers.txt
  assert_false "$name keeps the template list of the base config" grep -q 'builtin_ids' "$f"
  assert_false "$name's widgets follow the screen that is on, not one connector" grep -q '^output = ' "$f"
done

# noctalia-preset against a fake noctalia that remembers the wallpaper.
mkdir -p "$tmp/bin" "$tmp/home/.config/noctalia-presets"
cat >"$tmp/bin/noctalia" <<'FAKE'
#!/usr/bin/env bash
state="$HOME/wallpaper"
case "$2" in
  wallpaper-get) cat "$state" ;;
  wallpaper-set) echo "$3" >"$state" ;;
esac
FAKE
chmod +x "$tmp/bin/noctalia"
echo /walls/old.jpg >"$tmp/home/wallpaper"
run() { HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state" PATH="$tmp/bin:$PATH" bin/noctalia-preset "$@"; }
active="$tmp/home/.config/noctalia/30-preset.toml"

assert_true "the list shows waterfall" grep -q ' waterfall ' <<<"$(run)"
run waterfall >/dev/null
assert_eq "$PWD/config/noctalia/presets/waterfall.toml" "$(readlink "$active")" "waterfall links the repo's preset"
assert_eq "$tmp/home/Pictures/Wallpapers/wallhaven-rq6j57.png" "$(cat "$tmp/home/wallpaper")" "waterfall sets its wallpaper"
assert_true "the list marks waterfall active" grep -q '^\* waterfall ' <<<"$(run)"
run night >/dev/null
run off >/dev/null
assert_false "off removes the preset" test -e "$active"
assert_eq "/walls/old.jpg" "$(cat "$tmp/home/wallpaper")" "off brings back the wallpaper from before the first preset"
printf '# Preset "waterfall": mine.\n[theme]\nsource = "builtin"\n' >"$tmp/home/.config/noctalia-presets/waterfall.toml"
run waterfall >/dev/null
assert_eq "$tmp/home/.config/noctalia-presets/waterfall.toml" "$(readlink "$active")" "your own preset wins over the repo's"
assert_false "an unknown preset is refused" run nope
finish
