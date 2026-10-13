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
