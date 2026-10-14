# fedora-hyprland

One command turns a fresh **Fedora 44 Minimal** install into a complete **Hyprland + Noctalia v5** desktop,
in the spirit of CachyOS's Hyprland/Noctalia edition, but on a stable Fedora base.

You get Hyprland with Noctalia (bar, launcher, notifications, lock screen, wallpapers), the Noctalia login screen,
Ayu colors everywhere, Papirus icons, Ghostty, Thunar, Firefox, codecs, gaming (Steam, ProtonPlus, Heroic),
dev tools (VS Code, JetBrains Toolbox, GitHub CLI, Docker, Podman, Python 3.12–3.14, Node.js LTS), Flathub apps,
fingerprint login, printing, automatic btrfs snapshots before every update, Pika Backup, and one `update` command for everything.

## Before you start

1. Download the Fedora 44 **Everything** netinstall ISO and choose **Minimal Install**.
   On a laptop without a network cable, also tick **Hardware Support** and **Common NetworkManager Submodules**,
   otherwise Wi-Fi doesn't work after the first boot.
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

First it shows the language, keyboard layout and timezone you picked in the Fedora installer. Press Enter to keep them,
or answer `n` to choose others. Hyprland and the login screen use the system keyboard layout. To change it later:
`sudo localectl set-x11-keymap us`, then `update`.

At the end it may ask four questions: enroll a fingerprint, take hourly snapshots of `/home`, add system snapshots to
the boot menu, and install the ArtCraft Launcher (alpha creative apps). A "no" is remembered, so you aren't asked again.

## Snapshots and backups

- **System:** snapper snapshots `/` before and after every package change (see *If something breaks*).
- **Boot menu (optional):** [grub-btrfs](https://github.com/Antynea/grub-btrfs) adds a **Fedora snapshots** submenu to
  GRUB, so you can start the system as it was before an update even when it no longer boots normally.
- **Your files (optional):** hourly snapshots of `/home`, 12 hourly and 7 daily kept. Restore a deleted or overwritten
  file from Btrfs Assistant → Snapper → home, or copy it out of `/home/.snapshots/<number>/snapshot/` without sudo.
- **Backups:** snapshots live on the same disk, so they don't survive a dead SSD or a lost laptop. Open **Pika Backup**,
  pick an external drive or a server, and turn on its schedule. Pika's backups are encrypted and deduplicated.

## Update

```bash
update
```

It upgrades system packages (snapper takes a snapshot before and after), rebuilds the NVIDIA module for a new kernel
if you have one, updates Flatpaks and firmware, pulls this repo and re-runs `install.sh` so new defaults arrive.

## Keybinds

The CachyOS `cachyos-hypr-noctalia` set. Super is the Windows key.

**Apps**

| Keys | Action |
|---|---|
| Super+Return | Ghostty (opens instantly: Ghostty keeps running in the background) |
| Super+E / W / T / C | Thunar / Firefox / text editor / calculator |
| Calculator key | calculator |
| Ctrl+Shift+Escape | btop |

**Windows**

| Keys | Action |
|---|---|
| Super+Q, Super+Escape | close window, force-kill (click a window) |
| Super+F, Super+D, Super+Alt+Space | fullscreen, maximize, float |
| Super+J | swap with the main window |
| Super+arrows, Super+Shift+arrows | move focus, move window |
| Alt+Tab, Super+Tab | cycle windows, window switcher |
| Super+S | scratchpad |
| Super+mouse drag (left / right) | move / resize window |
| Super+Minus / Plus | zoom |

**Noctalia**

| Keys | Action |
|---|---|
| Super+Space, Super+. | launcher, emoji picker |
| Super+X, Super+Z, Super+A | control center, settings, notifications |
| Super+V, Super+P | clipboard history, color picker |
| Super+L, Super+Alt+C | lock, session menu |
| Super+Shift+W | wallpaper picker |
| Print / Super+Print | screenshot of a region / of the screen |
| Super+Shift+S | start / stop screen recording (asks what to record; saved to ~/Videos/Recordings) |

**Hardware keys and touchpad.** Volume, mic, media and brightness keys also work on the lock screen.

| Keys | Action |
|---|---|
| Volume up / down / mute, mic mute | volume and microphone (hold to repeat) |
| Play/Pause, Next, Previous | media control |
| Brightness up / down | screen brightness (hold to repeat) |
| Three-finger swipe sideways | switch workspace |

**Desks:** there are five linked desks. Each desk is a pair of workspaces, one per monitor.
Every session starts on desk 1, so the first apps you open land there.

| Keys | Action |
|---|---|
| Super+1..5 | switch both monitors to desk 1–5 |
| Ctrl+Super+Left / Right | previous / next desk (stops at desk 1 and 5) |
| Super+Shift+1..5 | send the window to desk 1–5 on its monitor (you stay where you are) |
| Ctrl+Super+Shift+Left / Right | take the window to the previous / next desk (you go with it) |
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

## Power profiles

Noctalia's power toggle switches TuneD profiles. **Balanced** runs at full speed on AC and switches to plain
balanced on battery. Fedora's default is the more aggressive balanced-battery, which roughly doubles app start
times. Pick **Power saver** when you need the battery to last.

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
- **Bad update and it won't boot:** in GRUB, open **Fedora snapshots** and pick the snapshot from before the update.
  `/boot` isn't part of the snapshots, so choose a kernel that was already installed back then (the older ones in the
  list). The snapshot starts read-only and some services may complain. That's expected. Open Btrfs Assistant, restore
  that snapshot and reboot. **Untested on real hardware so far.**
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
