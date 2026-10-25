#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

failures=0
for script in scripts/*.sh tests/*.sh packages/*/PKGBUILD packages/omarchy-jetson-session/omarchy-jetson-session.install packages/omarchy-jetson-upstream/omarchy-launch-terminal packages/omarchy-jetson-upstream/omarchy-terminal-context packages/omarchy-jetson-upstream/terminal-context.bashrc packages/omarchy-jetson-upstream/omarchy-jetson-reload-hyprland packages/omarchy-jetson-upstream/omarchy-jetson-upstream.install packages/omarchy-jetson-upstream/omarchy-jetson-shell packages/omarchy-jetson-upstream/omarchy-jetson-theme-set packages/omarchy-jetson-upstream/omarchy-jetson-qt612-shell-fix packages/omarchy-jetson-upstream/20-omarchy-jetson packages/omarchy-jetson-upstream/omarchy-jetson.sh packages/omarchy-jetson-actions/omarchy-capture-screenrecording packages/omarchy-jetson-input/omarchy-jetson-input packages/omarchy-jetson-menu/omarchy-menu packages/omarchy-jetson-menu/omarchy-jetson-display packages/omarchy-jetson-menu/omarchy-jetson-appearance packages/omarchy-jetson-menu/omarchy-jetson-power packages/omarchy-jetson-recovery/omarchy-jetson-snapshot packages/omarchy-jetson-session/omarchy-jetson-idle-lock packages/omarchy-jetson-updates/omarchy-jetson-auto-update packages/omarchy-jetson-updates/omarchy-jetson-update-settings packages/omarchy-jetson-updates/omarchy-jetson-update-notify packages/omarchy-jetson-updates/omarchy-jetson-updates.install packages/omarchy-jetson-kernel-safety/omarchy-jetson-kernel packages/omarchy-jetson-onboarding/omarchy-jetson-onboard packages/omarchy-jetson-onboarding/omarchy-jetson-onboarding.install config/makepkg-aarch64.conf; do
  if bash -n "$script"; then
    printf 'PASS  bash -n %s\n' "$script"
  else
    printf 'FAIL  bash -n %s\n' "$script" >&2
    failures=$((failures + 1))
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck scripts/*.sh tests/*.sh packages/omarchy-jetson-upstream/omarchy-launch-terminal packages/omarchy-jetson-upstream/omarchy-terminal-context packages/omarchy-jetson-upstream/terminal-context.bashrc packages/omarchy-jetson-upstream/omarchy-jetson-reload-hyprland packages/omarchy-jetson-upstream/omarchy-jetson-upstream.install packages/omarchy-jetson-upstream/omarchy-jetson-shell packages/omarchy-jetson-upstream/omarchy-jetson-theme-set packages/omarchy-jetson-upstream/omarchy-jetson-qt612-shell-fix packages/omarchy-jetson-upstream/20-omarchy-jetson packages/omarchy-jetson-upstream/omarchy-jetson.sh packages/omarchy-jetson-actions/omarchy-capture-screenrecording packages/omarchy-jetson-menu/omarchy-menu packages/omarchy-jetson-menu/omarchy-jetson-display packages/omarchy-jetson-menu/omarchy-jetson-appearance packages/omarchy-jetson-menu/omarchy-jetson-power packages/omarchy-jetson-recovery/omarchy-jetson-snapshot packages/omarchy-jetson-session/omarchy-jetson-idle-lock packages/omarchy-jetson-updates/omarchy-jetson-auto-update packages/omarchy-jetson-updates/omarchy-jetson-update-settings packages/omarchy-jetson-updates/omarchy-jetson-update-notify packages/omarchy-jetson-updates/omarchy-jetson-updates.install packages/omarchy-jetson-kernel-safety/omarchy-jetson-kernel packages/omarchy-jetson-onboarding/omarchy-jetson-onboard packages/omarchy-jetson-onboarding/omarchy-jetson-onboarding.install; then
    printf 'PASS  shellcheck\n'
  else
    failures=$((failures + 1))
  fi
else
  printf 'WARN  shellcheck unavailable; CI will enforce it\n'
fi

required_keys=(
  JETSON_LINUX_RELEASE JETPACK_RELEASE JETSON_KERNEL_RELEASE
  JETSON_BOARD_CONFIG TARGET_ARCH TARGET_ROOT_DEVICE
  ARCH_ROOTFS_URL ARCH_ROOTFS_SIGNATURE_URL ARCH_ROOTFS_SIGNING_KEY
  OMARCHY_REPOSITORY OMARCHY_REF
)

# shellcheck disable=SC1091
source config/versions.env
for key in "${required_keys[@]}"; do
  if [[ -n "${!key:-}" ]]; then
    printf 'PASS  config key %s\n' "$key"
  else
    printf 'FAIL  missing config key %s\n' "$key" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$JETSON_BOARD_CONFIG" == 'jetson-agx-orin-devkit' && "$TARGET_ARCH" == 'aarch64' ]]; then
  printf 'PASS  target tuple\n'
else
  printf 'FAIL  unexpected target tuple\n' >&2
  failures=$((failures + 1))
fi

pkg_kernel_release=$(JETSON_BSP_DIR=/nonexistent bash -c 'source packages/linux-jetson/PKGBUILD; printf %s "$_kernelrelease"')
if [[ "$pkg_kernel_release" == "$JETSON_KERNEL_RELEASE" ]]; then
  printf 'PASS  kernel package ABI matches configuration\n'
else
  printf 'FAIL  kernel package ABI does not match configuration\n' >&2
  failures=$((failures + 1))
fi

initrd_kernel_release=$(JETSON_INITRD=/nonexistent bash -c 'source packages/linux-jetson-initrd/PKGBUILD; printf %s "$_kernelrelease"')
if [[ "$initrd_kernel_release" == "$JETSON_KERNEL_RELEASE" ]]; then
  printf 'PASS  initrd package ABI matches configuration\n'
else
  printf 'FAIL  initrd package ABI does not match configuration\n' >&2
  failures=$((failures + 1))
fi

if rg -q '/opt/nvidia/l4t-gpu-libs/nvgpu' packages/nvidia-jetson-userspace/PKGBUILD &&
  ! rg -q '/opt/nvidia/l4t-gpu-libs/openrm' packages/nvidia-jetson-userspace/PKGBUILD; then
  printf 'PASS  userspace package is pinned to the Orin NVGPU variant\n'
else
  printf 'FAIL  userspace package GPU variant is ambiguous\n' >&2
  failures=$((failures + 1))
fi

binding_modules=(media clipboard tiling utilities voxtype applications)
binding_config=config/rootfs/hyprland.lua
upstream_package=packages/omarchy-jetson-upstream/PKGBUILD
binding_contract_ok=true

for module in "${binding_modules[@]}"; do
  if ! rg -Fq "require(\"default.hypr.bindings.$module\")" "$binding_config"; then
    printf 'FAIL  missing Omarchy binding module %s\n' "$module" >&2
    binding_contract_ok=false
  fi
done

# The binding tree now comes from upstream's `omarchy` package; the Jetson layer
# depends on it and replaces the packages that used to vendor a pinned copy.
if [[ $binding_contract_ok == true ]] &&
  rg -Fq 'omarchy_preinstalled_bindings = false' "$binding_config" &&
  rg -Fq 'local omarchy_config_tree = "/usr/share/omarchy"' "$binding_config" &&
  rg -Fq "depends=('omarchy' 'omarchy-settings'" "$upstream_package" &&
  rg -Fq "replaces=('omarchy-jetson-bindings' 'omarchy-jetson-quattro-shell' 'omarchy-jetson-quattro-themes')" "$upstream_package" &&
  [[ ! -e packages/omarchy-jetson-bindings && ! -e packages/omarchy-jetson-quattro-shell && ! -e packages/omarchy-jetson-quattro-themes ]]; then
  printf 'PASS  upstream Omarchy core binding contract\n'
else
  printf 'FAIL  Omarchy binding contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

menu_package=packages/omarchy-jetson-menu/PKGBUILD
menu_adapter=packages/omarchy-jetson-menu/omarchy-menu
if ! rg -Fq "'SKIP'" "$menu_package" &&
  rg -Fq 'toggle|summon) open_route "$route"' "$menu_adapter" &&
  rg -Fq "\$'apps\\tApplications'" "$menu_adapter" &&
  rg -Fq "\$'system\\tSystem'" "$menu_adapter"; then
  printf 'PASS  capability-aware Omarchy menu adapter\n'
else
  printf 'FAIL  Omarchy menu adapter contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

shell_service=packages/omarchy-jetson-upstream/omarchy-jetson-shell.service
shell_launcher=packages/omarchy-jetson-upstream/omarchy-jetson-shell
shell_config=packages/omarchy-jetson-upstream/default-shell.json
if ! rg -Fq "'SKIP'" "$upstream_package" &&
  rg -Fq "arch=('aarch64')" "$upstream_package" &&
  rg -Fq 'Restart=on-failure' "$shell_service" &&
  rg -Fq 'Environment=OMARCHY_PATH=/usr/share/omarchy' "$shell_service" &&
  rg -Fq 'event=crashed' "$shell_launcher" &&
  ! rg -qi 'waybar' "$shell_launcher" &&
  ! rg -q 'omarchy-quattro' "$shell_launcher" "$shell_service" &&
  jq -e '.disabledPlugins | index("omarchy.notifications") and index("omarchy.lock") and index("omarchy.polkit")' "$shell_config" >/dev/null &&
  rg -Fq 'systemctl --user start omarchy-jetson-shell.service' config/rootfs/hyprland.lua; then
  printf 'PASS  supervised upstream Omarchy shell service\n'
else
  printf 'FAIL  Omarchy shell service contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

# Jetson hardware overrides live in /usr/lib/omarchy-jetson/bin and must come
# first on PATH; upstream's copies stay untouched in /usr/bin.
overrides_env=packages/omarchy-jetson-upstream/20-omarchy-jetson
if rg -Fq 'local overrides="$pkgdir/usr/lib/omarchy-jetson/bin"' "$upstream_package" &&
  rg -Fq '"$overrides/omarchy-launch-terminal"' "$upstream_package" &&
  rg -Fq 'usr/lib/omarchy-jetson/bin/omarchy-capture-screenrecording' packages/omarchy-jetson-actions/PKGBUILD &&
  ! rg -Fq '/usr/bin/omarchy-capture' packages/omarchy-jetson-actions/PKGBUILD &&
  rg -Fq 'PATH="/usr/lib/omarchy-jetson/bin' "$overrides_env" &&
  rg -Fq 'usr/share/uwsm/env.d/20-omarchy-jetson' "$upstream_package" &&
  rg -Fq 'etc/profile.d/omarchy-jetson.sh' "$upstream_package" &&
  ! rg -Fq '/usr/bin/omarchy-system-lock' packages/omarchy-jetson-session/PKGBUILD &&
  ! rg -Fq '/usr/bin/omarchy-menu-keybindings' packages/omarchy-jetson-menu/PKGBUILD; then
  printf 'PASS  Jetson overrides ship outside /usr/bin and lead PATH\n'
else
  printf 'FAIL  Jetson override layout is incomplete\n' >&2
  failures=$((failures + 1))
fi

# Qt 6.12 shadows the shell's Color singleton; upstream fixed it after v4.0.4.
qt612_fix=packages/omarchy-jetson-upstream/omarchy-jetson-qt612-shell-fix
qt612_hook=packages/omarchy-jetson-upstream/90-omarchy-jetson-qt612-shell-fix.hook
if rg -Fq "pragma='//@ pragma OmarchyLoadPatch'" "$qt612_fix" &&
  rg -Fq 'grep -qxF "$pragma" "$shell_qml" && exit 0' "$qt612_fix" &&
  rg -Fq 'Target = omarchy' "$qt612_hook"; then
  printf 'PASS  idempotent Qt 6.12 shell fix hook\n'
else
  printf 'FAIL  Qt 6.12 shell fix hook is incomplete\n' >&2
  failures=$((failures + 1))
fi

theme_applier=packages/omarchy-jetson-upstream/omarchy-jetson-theme-set
if rg -Fq 'export OMARCHY_PATH=' "$theme_applier" &&
  rg -Fq 'call background refresh' "$theme_applier" &&
  ! rg -q 'omarchy-quattro' "$theme_applier" &&
  ! rg -Fq '"$pkgdir/usr/bin/omarchy-menu"' packages/omarchy-jetson-menu/PKGBUILD &&
  rg -Fq 'hl.env("OMARCHY_PATH", "/usr/share/omarchy")' config/rootfs/hyprland.lua &&
  rg -Fq 'disable_splash_rendering = true' config/rootfs/hyprland.lua; then
  printf 'PASS  theme pipeline and menu IPC come from upstream Omarchy\n'
else
  printf 'FAIL  Omarchy theme/menu alignment contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

menu_extension=packages/omarchy-jetson-upstream/default-menu-extension.jsonc
if jq -e '.items["style.appearance"] and .items["style.display"] and .items["setup.jetson-power"]' \
  <(rg -v '^\s*//' "$menu_extension") >/dev/null &&
  ! rg -q 'SUPER \+ SHIFT \+ CTRL \+ A' config/rootfs/hyprland.lua &&
  rg -Fq 'default-menu-extension.jsonc' "$shell_launcher" &&
  rg -Fq 'default-menu-extension.jsonc' "$upstream_package" &&
  rg -Fq 'package.path = omarchy_config_tree' config/rootfs/hyprland.lua; then
  printf 'PASS  Jetson Style/Setup menu additions and upstream agent picker binding\n'
else
  printf 'FAIL  Jetson menu additions or upstream binding contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

if jq -e '[.bar.layout.center[].id] | index("omarchy.weather")' "$shell_config" >/dev/null &&
  ! jq -e '[.bar.layout.center[].id] | index("omarchy.system-update")' "$shell_config" >/dev/null; then
  printf 'PASS  bar layout\n'
else
  printf 'FAIL  bar layout contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

input_command=packages/omarchy-jetson-input/omarchy-jetson-input
wlrctl_package=packages/wlrctl/PKGBUILD
if rg -Fq 'hl.dsp.cursor.move({ x = %d, y = %d })' "$input_command" &&
  rg -Fq 'wlrctl pointer click' "$input_command" &&
  rg -Fq 'wtype' "$input_command" &&
  ! rg -q '^[^#]*\bydotool\b' "$input_command" &&
  rg -Fq 'b5b3836091c41de09a832df1e5eb4747841d7ae670367e413487d5be7a5f2849' "$wlrctl_package" &&
  rg -Fq 'ARM aarch64' "$wlrctl_package"; then
  printf 'PASS  virtual input works without USB HID or uinput\n'
else
  printf 'FAIL  virtual input contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

menu_generator=scripts/generate-menu-extension.py
menu_additions=packages/omarchy-jetson-upstream/menu-additions.jsonc
generated_menu=packages/omarchy-jetson-upstream/default-menu-extension.jsonc
if [[ -x $menu_generator ]] &&
  rg -Fq 'GENERATED by scripts/generate-menu-extension.py' "$generated_menu" &&
  rg -Fq 'command -v' "$generated_menu" &&
  rg -Fq 'HOME/.local/share/mise/shims' "$shell_launcher" &&
  jq -e '.items["style.appearance"] and .items["setup.jetson-power"]' \
    <(rg -v '^\s*//' "$menu_additions") >/dev/null; then
  printf 'PASS  generated menu guards and shell PATH reach the packaged commands\n'
else
  printf 'FAIL  menu guard generation contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

ttfx_package=packages/ttfx/PKGBUILD
if rg -Fq 'omarchy-jetson-screensaver effect-args' "$upstream_package" &&
  rg -Fq '"$overrides/omarchy-screensaver"' "$upstream_package" &&
  rg -Fq 'd0c0df4867e7f03142fb7f77c66670d0e8da15534239c1a7abfd89f19dfc00f6' "$ttfx_package" &&
  rg -Fq "ARM aarch64" "$ttfx_package"; then
  printf 'PASS  screensaver effect override and pinned ttfx\n'
else
  printf 'FAIL  screensaver effect override or ttfx contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

# mise comes from upstream Omarchy's signed [omarchy] repo (mise-bin), as on
# stock Omarchy; this project no longer builds a pinned copy of its own.
if [[ ! -e packages/mise ]]; then
  printf 'PASS  mise from upstream (no local mise package)\n'
else
  printf 'FAIL  local mise package present\n' >&2
  failures=$((failures + 1))
fi

power_package=packages/nvidia-jetson-power/PKGBUILD
if rg -Fq 'nvpmodel_p3701_0000.conf' "$power_package" &&
  rg -Fq "test ! -e \"\$pkgdir/usr/lib/systemd/system/nvpmodel.service\"" "$power_package"; then
  printf 'PASS  nvpmodel package is target-specific and not auto-enabled\n'
else
  printf 'FAIL  nvpmodel package target or enablement policy is unsafe\n' >&2
  failures=$((failures + 1))
fi

cdi_package=packages/nvidia-container-toolkit/PKGBUILD
cdi_service=packages/nvidia-container-toolkit/nvidia-cdi-refresh-jetson.service
cdi_csv=packages/nvidia-container-toolkit/arch-linux.csv
if ! rg -Fq "'SKIP'" "$cdi_package" &&
  rg -Fq 'ConditionPathExists=/dev/nvhost-gpu' "$cdi_service" &&
  rg -Fq 'RuntimeDirectoryPreserve=yes' "$cdi_service" &&
  rg -Fq -- '--mode=csv' "$cdi_service" &&
  rg -Fq -- '--output=/run/cdi/nvidia.yaml' "$cdi_service" &&
  rg -Fq 'multi-user.target.wants/nvidia-cdi-refresh.path' "$cdi_package" &&
  rg -Fq 'lib, /opt/nvidia/l4t-gpu-libs/nvgpu/libcuda.so.1.1' "$cdi_csv"; then
  printf 'PASS  Jetson CUDA CDI generation contract\n'
else
  printf 'FAIL  Jetson CUDA CDI generation contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

vscode_package=packages/visual-studio-code-bin/PKGBUILD
vscode_desktop=packages/visual-studio-code-bin/visual-studio-code.desktop
vscode_apparmor=packages/visual-studio-code-bin/visual-studio-code.apparmor
vscode_launcher=packages/visual-studio-code-bin/code-jetson
if ! rg -Fq "'SKIP'" "$vscode_package" &&
  rg -Fq "arch=('aarch64')" "$vscode_package" &&
  rg -Fq 'update.code.visualstudio.com/${pkgver}/linux-arm64/stable' "$vscode_package" &&
  rg -Fq 'Exec=code --ozone-platform-hint=auto %F' "$vscode_desktop" &&
  rg -Fq '/opt/visual-studio-code/code flags=(unconfined)' "$vscode_apparmor" &&
  rg -Fq '  userns,' "$vscode_apparmor" &&
  rg -Fq 'exec /opt/visual-studio-code/bin/code --disable-gpu "$@"' "$vscode_launcher"; then
  printf 'PASS  pinned official VS Code AArch64 package contract\n'
else
  printf 'FAIL  VS Code AArch64 package contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

bwrap_apparmor=packages/omarchy-jetson-session/bwrap.apparmor
session_package=packages/omarchy-jetson-session/PKGBUILD
if rg -Fq 'profile bwrap /usr/bin/bwrap flags=(unconfined)' "$bwrap_apparmor" &&
  rg -Fq '  userns,' "$bwrap_apparmor" &&
  rg -Fq '"$pkgdir/etc/apparmor.d/bwrap"' "$session_package" &&
  rg -Fq 'apparmor_parser -r /etc/apparmor.d/bwrap' packages/omarchy-jetson-session/omarchy-jetson-session.install; then
  printf 'PASS  bwrap may create user namespaces (GTK image loaders, file chooser)\n'
else
  printf 'FAIL  bwrap AppArmor userns profile is missing\n' >&2
  failures=$((failures + 1))
fi

headers_package=packages/linux-jetson-headers/PKGBUILD
if ! rg -Fq "'SKIP'" "$headers_package" &&
  rg -Fq "arch=('aarch64')" "$headers_package" &&
  rg -Fq "_kernelrelease='6.8.12-1021-tegra'" "$headers_package" &&
  rg -Fq "_headers_root='linux-headers-6.8.12-1021-tegra-ubuntu24.04_aarch64" "$headers_package" &&
  rg -Fq 'scripts/mod/modpost' "$headers_package"; then
  printf 'PASS  native Jetson kernel headers package contract\n'
else
  printf 'FAIL  native Jetson kernel headers package contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

development_package=packages/omarchy-jetson-development/PKGBUILD
if ! rg -Fq "'SKIP'" "$development_package" &&
  rg -Fq "'linux-jetson-headers=6.8.12.1021'" "$development_package" &&
  rg -Fq "'nvidia-jetson-cuda=13.2.86'" "$development_package" &&
  rg -Fq "'visual-studio-code-bin'" "$development_package" &&
  rg -Fq "'1password-cli'" "$development_package" &&
  ! rg -q "'(visual-studio-code-bin|1password-cli)[<>=]" "$development_package" &&
  rg -Fq "'python-numpy'" "$development_package" &&
  rg -Fq "'opencv'" "$development_package" &&
  ! rg -Fq "'python-opencv'" "$development_package"; then
  printf 'PASS  Jetson development environment package contract\n'
else
  printf 'FAIL  Jetson development environment package contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

onepassword_package=packages/1password-cli/PKGBUILD
if ! rg -Fq "'SKIP'" "$onepassword_package" &&
  rg -Fq "arch=('aarch64')" "$onepassword_package" &&
  rg -Fq "_signing_fingerprint='3FEF9748469ADBE15DA7CA80AC2D62742012EA22'" "$onepassword_package" &&
  rg -Fq 'file -b "$srcdir/op"' "$onepassword_package" &&
  rg -Fq 'gpgv --keyring' "$onepassword_package" &&
  rg -Fq '2755 root onepassword-cli' packages/1password-cli/onepassword-cli.tmpfiles; then
  printf 'PASS  publisher-verified 1Password CLI AArch64 package contract\n'
else
  printf 'FAIL  1Password CLI AArch64 package contract is incomplete\n' >&2
  failures=$((failures + 1))
fi

if jq -e '
  .schema == 1 and
  (.artifacts.archlinuxarm_rootfs.sha256 | test("^[0-9a-f]{64}$")) and
  (.artifacts.archlinuxarm_rootfs.signing_key_fingerprint | test("^[0-9A-F]{40}$")) and
  .artifacts.archlinuxarm_rootfs.signature_verified == true and
  (.artifacts.nvidia_jetson_linux_bsp.sha1 | test("^[0-9a-f]{40}$")) and
  (.artifacts.nvidia_jetson_linux_bsp.sha256 | test("^[0-9a-f]{64}$")) and
  (.artifacts.nvidia_jetson_linux_bsp.l4t_initrd_sha256 | test("^[0-9a-f]{64}$")) and
  .artifacts.nvidia_jetson_linux_bsp.sha1_matches_publisher_manifest == true and
  (.artifacts.omarchy.commit | test("^[0-9a-f]{40}$"))
' config/inputs.lock.json >/dev/null; then
  printf 'PASS  input lock schema and digests\n'
else
  printf 'FAIL  input lock schema or digests\n' >&2
  failures=$((failures + 1))
fi

if rg -n --glob '*.sh' --glob '!write-usb-test-drive.sh' --glob 'Makefile' '(^|[[:space:]])(rm[[:space:]]+-rf|mkfs\.|wipefs|dd[[:space:]].*of=/dev/|l4t_initrd_flash\.sh|flash\.sh|parted[[:space:]].*mklabel)' .; then
  printf 'FAIL  destructive or flashing command present outside the guarded USB writer\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS  no destructive or flashing command outside the guarded USB writer\n'
fi

usb_writer=scripts/write-usb-test-drive.sh
if rg -q 'TRAN.*usb' "$usb_writer" &&
  rg -q 'RM.*== 1' "$usb_writer" &&
  rg -q 'actual_serial.*confirmed_serial' "$usb_writer" &&
  rg -q 'write == 0' "$usb_writer" &&
  rg -q 'EUID == 0' "$usb_writer"; then
  printf 'PASS  USB writer has transport, removability, serial, dry-run, and privilege guards\n'
else
  printf 'FAIL  USB writer is missing a required destructive-operation guard\n' >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  printf 'Static validation failed with %d issue(s).\n' "$failures" >&2
  exit 1
fi

printf 'Static validation passed.\n'
