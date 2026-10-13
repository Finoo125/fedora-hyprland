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

# environment.d reaches Hyprland (a uwsm user unit) and every app started with `uwsm app`.
assert_true  "hybrid renders on the iGPU"      grep -qx 'AQ_DRM_DEVICES=/dev/dri/igpu:/dev/dri/dgpu' <<<"$(gpu_env hybrid)"
assert_false "hybrid doesn't force GLX nvidia" grep -qF '__GLX_VENDOR_LIBRARY_NAME' <<<"$(gpu_env hybrid)"
assert_true  "dedicated sets VA-API to nvidia" grep -qx 'LIBVA_DRIVER_NAME=nvidia' <<<"$(gpu_env dedicated)"

# Module build: for the newest installed kernel (the one the next boot uses), with its headers, and retried with --force.
calls=(); module_ok=no
rpm() { printf '6.19.8-300.fc44.x86_64\n7.0.2-200.fc44.x86_64\n'; }
modinfo() { [[ $module_ok == yes ]]; }
sudo() { calls+=("$*"); if [[ "$1" == akmods ]]; then module_ok=yes; fi; }
nvidia_build
built=$(printf '%s\n' "${calls[@]}")
assert_true "headers for the newest kernel are installed" grep -qx 'dnf install -y kernel-devel-7.0.2-200.fc44.x86_64' <<<"$built"
assert_true "module is force-built for the newest kernel" grep -qx 'akmods --force --kernels 7.0.2-200.fc44.x86_64' <<<"$built"
calls=()
nvidia_build
assert_eq "" "${calls[*]}" "an existing module isn't rebuilt on every run"
unset -f rpm modinfo sudo
finish
