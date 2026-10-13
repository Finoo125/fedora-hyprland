# Fedora Hyprland Installer — Design

- **Date:** 2026-10-13
- **Status:** Approved 2026-10-13
- **Repo:** `github.com/Finoo125/fedora-hyprland` (public)

## Goal

One command turns a fresh **Fedora 44 Minimal** install into a complete **Hyprland + Noctalia v5** desktop
with the "finished" feel of CachyOS's `cachyos-hypr-noctalia` edition, on a stable Fedora base.

Target machines (both Intel-only, identical setup):

- HP EliteBook 650 G9 (Alder Lake)
- Framework 13 Pro, Intel Core Ultra X7 358H (Panther Lake)

### Success criteria

1. Fresh Fedora 44 Minimal → `git clone … && ./install.sh` → reboot → Noctalia Greeter → working desktop.
   The only interactive steps are the sudo password, the optional fingerprint enrollment, the optional ArtCraft prompt,
   and (only on machines with an NVIDIA GPU) the driver prompt plus the Secure Boot key password.
2. Re-running `install.sh` is safe and is how updates to the defaults get applied.
3. Both laptops end up identical; plugging into the dock switches the monitor layout automatically, unplugging never leaves a black screen.

### Non-goals

Installing Fedora itself (Anaconda), migrating data from the existing KDE install, NVIDIA GPUs older than Turing
(GTX 10xx and earlier need RPM Fusion's legacy 580xx driver), AMD-specific tuning, other distros,
per-machine customization (until a real hardware difference shows up).

## Approach

A single bash installer plus a folder of config defaults (the Omarchy / minimaDots / JaKooLit pattern).

Rejected:

- **Ansible:** must be installed first, adds YAML indirection; overkill for two laptops.
- **Own COPR meta-package** (CachyOS style): spec files and a build pipeline to maintain. Can wrap this repo later without rewriting it.

## Repository layout

```
fedora-hyprland/                 cloned to ~/.local/share/fedora-hyprland
├── install.sh                   single entry point; sections are functions
├── bin/update                   one-shot updater (linked to ~/.local/bin/update)
├── config/
│   ├── hypr/                    Hyprland defaults (Lua), split by topic
│   ├── noctalia/                Noctalia defaults (TOML)
│   ├── ghostty/  uwsm/  gtk-3.0/  gtk-4.0/  qt6ct/  mimeapps.list
│   └── wallpapers.txt           pinned download URLs, first line = default
├── .github/workflows/ci.yml
├── LICENSE                      MIT
└── README.md
```

`install.sh` resolves its own directory, so config paths point at wherever the repo is cloned;
the README uses `~/.local/share/fedora-hyprland`.

## Config layering

Repo holds the **defaults**; the user's files hold **overrides**. `git pull` updates defaults on both laptops
without touching overrides.

| Config | Mechanism |
|---|---|
| Hyprland | `~/.config/hypr/hyprland.lua` is a user-owned stub, created once if missing: it `dofile()`s the repo's `config/hypr/hyprland.lua`, then holds the user's overrides (incl. the detected keyboard layout). |
| Noctalia | Noctalia merges every `*.toml` in `~/.config/noctalia/` alphabetically, then `~/.local/state/noctalia/settings.toml` (GUI changes) on top. The installer symlinks `~/.config/noctalia/00-fedora-hyprland.toml` → repo file. User files and GUI settings win. |
| Everything else (ghostty, gtk, qt6ct, mimeapps, uwsm env) | Copied once if the target does not exist; never overwritten. |

Hyprland and Noctalia defaults are **written fresh**, using `cachyos-hypr-noctalia` and the Noctalia docs as
references only (its files are GPL-1.0-only; we don't copy them).

## Package sources

| Source | Used for |
|---|---|
| Fedora 44 | everything possible, incl. `noctalia` 5.2.x |
| RPM Fusion free + nonfree | ffmpeg, codecs, `intel-media-driver`, `steam` |
| COPR `lionheartp/Hyprland` | `hyprland` (0.56.x), `xdg-desktop-portal-hyprland`, `uwsm`, `hyprpicker`, `nwg-look` (Hyprland is no longer in Fedora's official repos after F42) |
| Terra, limited via `includepkgs=noctalia-greeter* ghostty* bibata-cursor-theme*` | stable `noctalia-greeter`, `ghostty`, Bibata cursor; nothing else from Terra can replace Fedora packages. Terra's extra repos stay disabled. |
| Docker CE repo | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` |
| Microsoft VS Code repo | `code` |
| Flathub (system remote) | GUI apps below |

## Packages (dnf)

| Group | Packages |
|---|---|
| Desktop core | hyprland, uwsm, xdg-desktop-portal-hyprland, xdg-desktop-portal-gtk, noctalia, greetd, noctalia-greeter, pipewire, pipewire-pulseaudio, wireplumber, bluez, NetworkManager-wifi, nm-connection-editor, tuned-ppd, upower, gnome-keyring, ddcutil, bolt, qt5-qtwayland, qt6-qtwayland, qt6ct, nwg-look, adw-gtk3-theme, papirus-icon-theme, bibata-cursor-theme, xsettingsd, Noto + JetBrains Mono fonts, wl-clipboard, cliphist, grim, slurp, hyprpicker, xdg-user-dirs, xdg-utils |
| Apps | ghostty, Thunar, thunar-archive-plugin, thunar-volman, tumbler, ffmpegthumbnailer, gvfs, gvfs-mtp, gvfs-smb, file-roller, firefox, mpv, qview, papers, gnome-text-editor, gnome-calculator, gnome-software, kde-connect |
| CLI | git, wget, curl, fastfetch, btop, bat, eza, fzf, ripgrep, fd-find, zoxide, unzip, p7zip, bash-completion, plocate |
| Multimedia | full `ffmpeg` (swap from ffmpeg-free), `@multimedia` group, intel-media-driver, libva-utils |
| Gaming | steam, gamemode, mangohud, gamescope, lutris, protontricks, winetricks, vulkan-tools |
| AppImage | fuse-libs |
| Printing | cups, system-config-printer, avahi, nss-mdns |
| Fingerprint | fprintd, fprintd-pam |
| Stability | snapper, btrfs-assistant, libdnf5-plugin-actions, fwupd |
| Dev | gcc, make, uv, python3 (3.14), python3.12, python3.13, nodejs24 (current Active LTS; move to 26 once Fedora ships it), podman, distrobox, docker-ce stack, code |

Not installed because Noctalia v5 provides it: bar, launcher, notifications, lock screen, idle handling,
polkit agent, night light, wallpaper, OSD, session menu (replaces waybar, wofi, mako, hyprlock, hypridle,
hyprpolkitagent, swww).

## Flatpaks (Flathub)

| Group | App IDs |
|---|---|
| Chat / mail | com.discordapp.Discord, org.signal.Signal, org.telegram.desktop, com.rtosta.zapzap (WhatsApp), org.mozilla.Thunderbird |
| Media | org.videolan.VLC |
| Productivity | com.bitwarden.desktop, md.obsidian.Obsidian |
| Dev | io.dbeaver.DBeaverCommunity, org.localsend.localsend_app |
| Gaming | com.vysp3r.ProtonPlus (Proton-CachyOS, GE-Proton), com.heroicgameslauncher.hgl, io.github.Faugus.faugus-launcher |
| Utilities | it.mijorus.gearlever (AppImages), com.github.tchx84.Flatseal, io.missioncenter.MissionCenter |

## Other installs

- **JetBrains Toolbox:** latest tarball from JetBrains' release API into `~/.local/share/JetBrains/Toolbox`; it self-updates.
- **Claude Code:** official native installer; it self-updates.
- **ArtCraft Launcher (opt-in prompt, default no):** AppImage from the official `storytold/craft-launcher`
  GitHub releases only (never lookalike repos), verified against the release's `SHA256SUMS.txt`,
  stored in `~/Applications` and integrated via Gear Lever. Never runs as root. Checksum mismatch → skip with a warning.
- **Noctalia KDE Connect plugin:** installed via Noctalia's plugin mechanism.

## install.sh flow

1. **Pre-flight:** Fedora ≥ 44 (`/etc/os-release`), not run as root (calls `sudo` itself), network reachable.
   All output is also logged to `~/.cache/fedora-hyprland/install.log`.
2. **Repos:** RPM Fusion, COPR, Terra (limited), Docker, VS Code, Flathub. Each is skipped if already present.
3. **Packages:** dnf groups above, ffmpeg swap, multimedia group update.
4. **Flatpaks + other installs.**
5. **System configuration** (next section), then **NVIDIA** if detected and confirmed (section below).
6. **User configuration:** layering above, `~/.local/bin/update` link, `xdg-user-dirs-update`.
7. **Summary + optional steps:** fingerprint enrollment (`fprintd-enroll`), ArtCraft prompt, then "reboot now".

Idempotency: `dnf install` / `flatpak install` are no-ops when present; repo and file steps check before acting;
system config writes are overwrite-safe (same content each run). Optional prompts (fingerprint, ArtCraft, NVIDIA) only
appear while that item is not yet set up, so `update` → `install.sh` re-runs stay non-interactive.

## System configuration

| Area | Setting |
|---|---|
| Login | greetd `[default_session]` → `noctalia-greeter-session`, user `greeter`; session = Hyprland (uwsm). `systemctl set-default graphical.target`. |
| Keyboard | Layout read from `localectl` (set in Anaconda), applied to Hyprland (user stub) and the greeter config. |
| Fingerprint | `authselect enable-feature with-fingerprint`; enrollment offered at the end. |
| Snapshots | Only if `/` is btrfs: snapper config for `/`, pre/post snapshots around every dnf transaction via the dnf5 actions plugin, keep the last 10; Btrfs Assistant for browsing and restore. |
| Services | bluetooth, cups, avahi-daemon, tuned + tuned-ppd, docker, fwupd-refresh.timer; user added to `docker` group. |
| Firewall | `kdeconnect` service added to the default firewalld zone (pairing still requires confirmation on both devices). |
| Lid | systemd defaults: lid close suspends when undocked, is ignored when docked. |
| GNOME Software | runs in the background via XDG autostart under uwsm for update notifications. |
| Default apps | `mimeapps.list`: Thunar (folders), Papers (PDF), qView (images), mpv (video), Firefox (links), gnome-text-editor (text). |

## NVIDIA (optional, RTX 20 to RTX 50)

Runs only when an NVIDIA GPU is detected, and only after the user confirms (`NVIDIA=yes|no` env var skips the prompt).
Follows RPM Fusion's current HowTos (NVIDIA, Secure Boot, Optimus).

**Detection:** `lspci -nn -d 10de:` filtered to display controllers. The codename decides support:
`TU1xx` (RTX 20 / GTX 16), `GA1xx` (RTX 30), `AD1xx` (RTX 40), `GB2xx` (RTX 50) → supported.
Anything older (`GP`, `GM`, `GK`…) → warning pointing to RPM Fusion's legacy `580xx` driver, then skipped.
A second (Intel/AMD) GPU present → **hybrid** mode, otherwise **dedicated** mode.

**Steps, in this order:**

1. **Secure Boot** (only if `mokutil --sb-state` reports enabled), done *before* the driver is installed so the module is signed
   at build time: install `kmodtool akmods mokutil openssl`, `kmodgenca -a` (skipped if a key exists),
   `mokutil --import /etc/pki/akmods/certs/public_key.der` (asks for a one-time password).
   The installer warns that the blue MOK screen after reboot uses a **US keyboard layout**, so the password should avoid
   `y`, `z` and special characters (they sit elsewhere on a German keyboard).
2. **Driver:** `akmod-nvidia` (RPM Fusion nonfree; driver 595+ on Fedora 44 ships the **open kernel modules prebuilt by
   default**, which Blackwell/RTX 50 requires), `xorg-x11-drv-nvidia-cuda` (nvidia-smi, CUDA, NVENC/NVDEC),
   `xorg-x11-drv-nvidia-libs.i686` (Steam/32-bit games), `xorg-x11-drv-nvidia-power`, `libva-nvidia-driver` (VA-API).
   `nvidia-drm.modeset` is **not** set manually (already on by default; RPM Fusion warns it conflicts with Fedora's simpledrm patch).
3. **Build now, not in the background:** `akmods --force --kernels <running kernel>`, then `modinfo -F version nvidia`
   must succeed before the installer suggests a reboot (rebooting during the background build gives a black screen).
4. **Suspend:** `systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate`.
5. **Session environment**, written by the installer to `~/.config/environment.d/60-fedora-hyprland-gpu.conf`
   (machine-specific, not in the repo). systemd's user manager reads it, so it reaches Hyprland (a uwsm user unit)
   and every app started with `uwsm app` (changed from a `gpu.lua` during the final review: `hl.env` doesn't reach those apps):

| Mode | Settings |
|---|---|
| Dedicated (desktop) | `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct` |
| Hybrid (laptop) | Hyprland renders on the iGPU for battery life: udev rule creates stable `/dev/dri/igpu` and `/dev/dri/dgpu` symlinks from the PCI path (the wiki warns `cardN` numbers change between boots), `AQ_DRM_DEVICES=/dev/dri/igpu:/dev/dri/dgpu`. `NVreg_DynamicPowerManagement=0x02` in `/etc/modprobe.d/nvidia.conf` so the dGPU sleeps when idle. A `nvidia-run` wrapper (`__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only`) starts an app on the dGPU, e.g. Steam launch option `nvidia-run %command%`. `switcheroo-control` enabled. |

6. **Updates:** `bin/update` runs `akmods --kernels <newest installed kernel>` after `dnf upgrade` when `akmod-nvidia`
   is installed, so the module for a new kernel exists before the next reboot. Snapper's pre/post snapshot covers rollback.

**Recovery** (in the README): pick the previous kernel in GRUB, or roll back the last dnf transaction's snapshot in Btrfs Assistant.

## Hyprland defaults

### Monitors and docking

Matched by **model description**, so connector names (which differ between laptops and dock ports) don't matter.
Values taken from the current Windows setup (EDID names, positions, rotation):

```lua
hl.monitor({ output = "desc:HP Inc. HP E27q G5", mode = "preferred", position = "0x0",    scale = 1, transform = 3 }) -- portrait; upside down? use 1
hl.monitor({ output = "desc:HP Inc. HP X27i",    mode = "highrr",    position = "1440x0", scale = 1 }) -- 144 Hz if the dock allows
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })                       -- any other display
```

Event-driven dock handling (no polling), via `hl.on("monitor.added")` / `hl.on("monitor.removed")`:

- any external monitor present → disable `eDP-1`;
- last external monitor removed → re-enable `eDP-1` immediately.

Calibration knobs: `transform` (3 vs 1) and vertical alignment (top-aligned, as on Windows).

### Workspaces: 4 linked desks

- Workspaces **1–4** live on the main monitor (HP X27i), **11–14** on the portrait monitor (HP E27q G5).
- `Super+N` (N = 1..4) switches both: workspace `10+N` on the portrait monitor, then `N` on the main monitor (focus ends on main).
- `Super+Shift+N` moves the focused window to desk N on the monitor it's on. (Keys: see the keybind table; this deviates from CachyOS.)
- Undocked: `Super+N` switches only the laptop screen; on `monitor.removed`, windows from `10+N` move to `N` so nothing gets stranded.

### Layout

Master layout, no hard window limit (extra windows stack into the secondary column):

- main monitor and laptop screen: master left, stack right → 1 left, 2 stacked right;
- portrait monitor: master on top, stack below → 1 top, 1 bottom.

### Keybinds (CachyOS `cachyos-hypr-noctalia` set, Super = main modifier)

Same bindings as CachyOS, re-implemented (not copied). Digits are bound by keycode (`code:10`…), so they work on any keyboard layout.
Apps launch through `uwsm app --`.

| Keys | Action |
|---|---|
| Super+Return / E / W / T / C | ghostty / Thunar / Firefox / gnome-text-editor / gnome-calculator |
| Super+Q, Super+Escape | close window, `hyprctl kill` |
| Super+F, Super+D, Super+Alt+Space, Super+J | fullscreen, maximize, toggle floating, toggle split |
| Super+arrows, Super+Shift+arrows | move focus, move window |
| Alt+Tab, Super+Tab | cycle windows, Noctalia window switcher |
| Super+Space, Super+. | launcher, emoji picker |
| Super+X, Super+Z, Super+A | control center, settings, notifications |
| Super+V, Super+P | clipboard history, color picker (hyprpicker) |
| Super+L, Super+Alt+C | lock, session menu |
| Print / Super+Print | region / full screenshot (`noctalia msg screenshot-region` / `screenshot-fullscreen`) |
| Super+Shift+W | wallpaper panel |
| Super+S, Super+Shift+S | toggle scratchpad, move window to scratchpad |
| Ctrl+Shift+Escape | btop in ghostty |
| Super+Minus / Plus | cursor zoom |
| Super+mouse left / right drag | move / resize window |
| Media, volume, mic, brightness keys | `noctalia msg …`, also on the lock screen |

**Deviation from CachyOS, for the linked desks:**

| Keys | Action |
|---|---|
| Super+1..4 | switch linked desk (both monitors) |
| Super+Shift+1..4 | move window to desk N on its monitor |
| Super+Alt+1 / 2 | focus portrait / main monitor (CachyOS has this on Super+1/2) |

Plus the Noctalia-recommended decoration, blur layer rule and settings window rule.

### Look

Chosen in the Theme Lab demo:

```toml
# config/noctalia/00-fedora-hyprland.toml
[theme]
mode    = "dark"
source  = "builtin"
builtin = "Ayu"
```

- Icons: **Papirus-Dark** (`papirus-icon-theme`, Fedora), folder color matched to Ayu's gold via `papirus-folders -C yellow`
  (single script from the official PapirusDevelopmentTeam repo, pinned to a commit; not packaged in Fedora).
- Cursor: **Bibata** (`bibata-cursor-theme` from Terra, added to the `includepkgs` allowlist).
- Wallpaper: `fill_mode = "span"` across the 4000×2560 docked canvas (crop on a single screen). Ten picks, chosen by
  scoring 2,627 images from five GitHub collections against the Ayu palette and reviewing the best by eye.
  The collections have no redistribution license, so the images are **never committed**: `config/wallpapers.txt` lists raw
  GitHub URLs pinned to a commit SHA (content can't change under us), and the installer downloads missing ones into
  `~/Pictures/Wallpapers` (Noctalia's default browse folder, so Super+Shift+W shows all of them).

| # | Name | Source (repo @ pinned commit) |
|---|---|---|
| 1 (default) | Orbits | AngelJumbo/gruvbox-wallpapers `wallpapers/mix/solar-system.jpg` |
| 2 | Mountain sigil | AngelJumbo/gruvbox-wallpapers `wallpapers/minimalistic/gruv.jpg` |
| 3 | Event horizon | D3Ext/aesthetic-wallpapers `images/planet_minimal.png` |
| 4 | Comet field | D3Ext/aesthetic-wallpapers `images/colorful-planets.jpg` |
| 5 | Lotus glow | AngelJumbo/gruvbox-wallpapers `wallpapers/photography/ameenfahmy-mXpTl4jNKiA.jpg` |
| 6 | Reaching light | dharmx/walls `unsorted/a_hand_reaching_out_to_the_sky.jpg` |
| 7 | Low sun | AngelJumbo/gruvbox-wallpapers `wallpapers/minimalistic/sunset.png` |
| 8 | Moonwalk | vyrx-dev/Wallpapers `others/astronaut2.png` |
| 9 | Comet night | JaKooLit/Wallpaper-Bank `wallpapers/Comets-of-that-night.jpg` |
| 10 | Horizon sunset | JaKooLit/Wallpaper-Bank `wallpapers/Sun-Setting-Horizon.png` |

  Pinned commits: gruvbox-wallpapers `293774a`, aesthetic-wallpapers `e34f059`, walls `6bf4d73`, Wallpapers (vyrx) `53e29b3`,
  Wallpaper-Bank `c5e1780` (full SHAs in `config/wallpapers.txt`). A failed download warns and continues.

## bin/update

```
sudo dnf upgrade --refresh   (snapper takes pre/post snapshots automatically)
sudo akmods --kernels <newest kernel>   (only if akmod-nvidia is installed)
flatpak update -y
fwupdmgr refresh && fwupdmgr update
git -C <repo> pull --ff-only && <repo>/install.sh
```

## Error handling

- `set -euo pipefail`; each section prints a header; on failure the script stops with the failing step named and the log path.
  Re-running continues safely because every step is idempotent.
- Optional steps (fingerprint, ArtCraft, snapper on non-btrfs) skip with a warning instead of failing the run.
- Downloads use HTTPS; ArtCraft is checksum-verified; no `curl | sudo bash`.

## Testing

- **CI (GitHub Actions, every push):** `shellcheck` on `install.sh` and `bin/update`; Lua syntax check (`luac -p`) on `config/hypr/*.lua`;
  in a `fedora:44` container, add the repos and `dnf repoquery` every package name, which catches renamed or removed packages.
  `install.sh` only runs `main` when executed (not when sourced), so CI can reuse its package lists.
- **Manual:** Fedora 44 Minimal VM: run `install.sh` twice (second run must change nothing), reboot, log in.
  Then the real laptops, including dock/undock on the real monitors.
- **NVIDIA:** neither laptop has one, so the detection and codename mapping get a unit check in CI (sample `lspci` lines for
  TU/GA/AD/GB/GP, single and hybrid). The driver path itself needs a real RTX machine; until one is tested, the README
  marks NVIDIA support as untested.

## Assumptions and open items

- Portrait rotation `transform = 3` is derived from Windows' "Portrait (flipped)"; may need `1`.
- Every ArtCraft app is alpha/in development; opt-in only.
- Node.js moves from 24 to 26 when Fedora 44 packages it.
- Framework 13 Pro (Panther Lake) support relies on Fedora 44's current kernel and Mesa; verify after first install.
- Repo license: MIT.
- To verify against the real tools during implementation (each is a small, contained step; if a mechanism doesn't exist,
  the fallback is noted): Noctalia's plugin install for the KDE Connect plugin (fallback: README step via the plugin panel);
  how noctalia-greeter takes a keyboard layout (fallback: `XKB_DEFAULT_LAYOUT` in the greetd session command);
  Gear Lever's command-line integration for the ArtCraft AppImage (fallback: write the `.desktop` entry ourselves).
