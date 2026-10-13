# fedora-hyprland

One command turns a fresh **Fedora 44 Minimal** install into a complete **Hyprland + Noctalia v5** desktop,
in the spirit of CachyOS's Hyprland/Noctalia edition, but on a stable Fedora base.

You get Hyprland with Noctalia (bar, launcher, notifications, lock screen, wallpapers), the Noctalia login screen,
Ayu colors everywhere, Papirus icons, Ghostty, Thunar, Firefox, codecs, gaming (Steam, ProtonPlus, Heroic),
dev tools (VS Code, JetBrains Toolbox, Docker, Podman, Python 3.12–3.14, Node.js LTS), Flathub apps,
fingerprint login, printing, automatic btrfs snapshots before every update, and one `update` command for everything.

## Before you start

1. Download the Fedora 44 **Everything** netinstall ISO and choose **Minimal Install**.
2. Keep the default automatic partitioning (btrfs). Snapshots need it.
3. After the first boot, make sure you're online (`nmtui` for Wi-Fi).

## Install

```bash
sudo dnf install -y git
git clone https://github.com/Finoo125/fedora-hyprland ~/.local/share/fedora-hyprland
~/.local/share/fedora-hyprland/install.sh
systemctl reboot
```

Run it as your normal user; it asks for your password when it needs it. A full log is kept in
`~/.cache/fedora-hyprland/install.log`. If something fails, fix it and run `install.sh` again: finished steps are skipped.

At the end it may ask two questions: enroll a fingerprint, and install the ArtCraft Launcher (alpha creative apps).
A "no" is remembered, so you aren't asked again.

## Update

```bash
update
```

It upgrades system packages (snapper takes a snapshot before and after), rebuilds the NVIDIA module for a new kernel
if you have one, updates Flatpaks and firmware, pulls this repo and re-runs `install.sh` so new defaults arrive.

## Keybinds

The CachyOS `cachyos-hypr-noctalia` set. Super is the Windows key.

| Keys | Action |
|---|---|
| Super+Return / E / W / T / C | Ghostty / Thunar / Firefox / text editor / calculator |
| Super+Space, Super+. | launcher, emoji picker |
| Super+Q, Super+Escape | close window, force-kill (click a window) |
| Super+F, Super+D, Super+Alt+Space | fullscreen, maximize, float |
| Super+J | swap with the main window |
| Super+arrows, Super+Shift+arrows | move focus, move window |
| Alt+Tab, Super+Tab | cycle windows, window switcher |
| Super+X, Super+Z, Super+A | control center, settings, notifications |
| Super+V, Super+P | clipboard history, color picker |
| Super+L, Super+Alt+C | lock, session menu |
| Print / Super+Print | screenshot of a region / of the screen |
| Super+Shift+W | wallpaper picker |
| Super+S, Super+Shift+S | scratchpad, move window to scratchpad |
| Ctrl+Shift+Escape | btop |
| Super+Minus / Plus | zoom |
| Super+mouse drag (left / right) | move / resize window |

**Desks:** there are four linked desks. Each desk is a pair of workspaces, one per monitor.

| Keys | Action |
|---|---|
| Super+1..4 | switch both monitors to desk 1–4 |
| Super+Shift+1..4 | move the window to desk 1–4 on its monitor |
| Super+Alt+1 / 2 | focus the portrait / main monitor |

## Monitors and docking

The layout is set up for two HP monitors, matched by model name, so it works on any dock port and with both laptops:

- **HP E27q G5**: portrait, on the left
- **HP X27i**: on the right, at the highest refresh rate the dock allows

When an external monitor is connected, the laptop screen turns off. When the last one is unplugged, it turns back on
immediately. One wallpaper spans both monitors.

To use other monitors, run `hyprctl monitors` and put your own rules in `~/.config/hypr/hyprland.lua`, for example:

```lua
hl.monitor({ output = "desc:Dell Inc. DELL U2723QE", mode = "preferred", position = "0x0", scale = 1.5 })
```

If the portrait monitor shows the picture upside down, override its rotation with `transform = 1` instead of `3`.

## Your own changes

| Yours (created once, never overwritten) | Regenerated on every install.sh run |
|---|---|
| `~/.config/hypr/hyprland.lua` (put overrides at the bottom) | `~/.config/environment.d/60-fedora-hyprland-gpu.conf` (NVIDIA only) |
| `~/.config/ghostty/config`, `~/.config/gtk-*/settings.ini`, `~/.config/qt6ct/qt6ct.conf` | `~/.config/noctalia/10-fedora-hyprland-local.toml` |
| `~/.config/mimeapps.list`, `~/.config/uwsm/env` | `/etc/greetd/config.toml`, `/var/lib/noctalia-greeter/greeter.toml` |
| any other `~/.config/noctalia/*.toml`, and everything you change in Noctalia's Settings | |

The defaults themselves live in this repo (`config/`) and arrive with `update`.

## NVIDIA (RTX 20 to RTX 50)

**Untested on real hardware so far.** If the installer finds an RTX 20–50 or GTX 16 card, it offers RPM Fusion's driver
(open kernel modules, CUDA, NVENC, Steam 32-bit libraries, suspend fixes). `NVIDIA=yes` or `NVIDIA=no` skips the question.
Older cards get a pointer to RPM Fusion's legacy driver.

- **Secure Boot:** you set a one-time password. After the reboot a blue **MOK management** screen appears:
  Enroll MOK → Continue → Yes → password → Reboot. That screen uses a **US keyboard layout**, so use only letters a–x
  and digits in the password.
- **Hybrid laptops:** the desktop runs on the integrated GPU. Start a game on the NVIDIA GPU with `nvidia-run <app>`,
  or the Steam launch option `nvidia-run %command%`.

## If something breaks

- **Bad update:** open Btrfs Assistant → Snapper, and restore the snapshot taken before the update.
- **Won't boot to the desktop:** pick the previous kernel in the GRUB menu, or switch to a text console with
  Ctrl+Alt+F3, log in, and look at `~/.cache/fedora-hyprland/install.log`.

## Credits

- Keybind set from [CachyOS](https://github.com/CachyOS/cachyos-hypr-noctalia), written fresh for this repo.
- [Noctalia](https://github.com/noctalia-dev/noctalia), [Hyprland](https://hypr.land), the
  [lionheartp/Hyprland](https://copr.fedorainfracloud.org/coprs/lionheartp/Hyprland/) COPR and [Terra](https://terrapkg.com).
- Wallpapers belong to their authors and are downloaded from their repos during install, not stored here:
  [AngelJumbo/gruvbox-wallpapers](https://github.com/AngelJumbo/gruvbox-wallpapers),
  [D3Ext/aesthetic-wallpapers](https://github.com/D3Ext/aesthetic-wallpapers),
  [dharmx/walls](https://github.com/dharmx/walls),
  [vyrx-dev/Wallpapers](https://github.com/vyrx-dev/Wallpapers),
  [JaKooLit/Wallpaper-Bank](https://github.com/JaKooLit/Wallpaper-Bank).

## License

MIT for the code and configs in this repo. Wallpapers belong to their authors.
