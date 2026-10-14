# Delivery checklist

This is the delivery tracker. Check an item only when its acceptance evidence
exists on the real Jetson (or, for source-only checks, in CI). `R1` is the
initial release. `POST-R1` work must not displace unfinished `R1` work.

For each completed item, add the date, tested version/commit, command or manual
case, result and evidence location to `docs/review.md`. Reopen an item when its
dependency or target version changes. `make check` validates the repository but
does not by itself prove a target-runtime item.

Status snapshot: the machine boots Arch from NVMe with NVIDIA GPU/CUDA and runs
stock upstream Omarchy 4 with a thin Jetson layer. The remaining work is
reproducible flashing from clean media, a signed package channel and
release-level validation.

Item IDs are stable; the working order can change when a dependency requires it.

## R1 — platform and recovery

- [x] `R1-PLAT-01` Boot Arch Linux ARM from NVMe through the NVIDIA Jetson
  firmware/kernel/DTB boundary.
- [x] `R1-PLAT-02` Validate native GPU and CUDA with a known-answer test.
- [x] `R1-PLAT-03` Use zram for swap and exclude failing eMMC from routine use.
- [ ] `R1-PLAT-04` Record a repeatable, verified flash/recovery procedure and
  reproduce it from clean media.
- [x] `R1-PLAT-05` Add filesystem snapshot/rollback and prove one recovery.
- [ ] `R1-PLAT-06` Build a reproducible signed image/package channel with a
  pinned compatibility matrix.

## R1 — desktop and Omarchy compatibility

- [x] `R1-DESK-01` Boot a usable Hyprland/UWSM desktop with background, bar,
  notifications, audio and network controls.
- [x] `R1-DESK-02` Port and automatically compare all effective default
  shortcuts against the pinned upstream contract; remove provisional conflicts.
- [x] `R1-DESK-03` Implement Omarchy, application, plugin, system, keybinding,
  workspace and hardware menus. Discover optional capabilities at runtime,
  omit profile-excluded apps, and reserve unavailable-state explanations for
  core actions that should exist but are not yet implemented.
- [x] `R1-DESK-04` Implement monitor resolution, placement, refresh and scale
  controls plus text/UI scale controls; persist and rollback bad modes.
- [x] `R1-DESK-11` Ship upstream Omarchy's themes and background picker
  unchanged, applied through `omarchy-theme-set`.
- [x] `R1-DESK-05` Validate add/switch/move/close workspace flows through menu
  and upstream shortcuts.
- [x] `R1-DESK-06` Complete screenshot flows: full screen, region/window,
  clipboard/file, discoverable capture menu, and filename/notification checks.
- [x] `R1-DESK-07` Port supported recording, OCR and colour-picker actions
  without changing upstream shortcuts.
- [x] `R1-DESK-08` Validate Brave, Foot, file manager, lock/idle, portals,
  clipboard, PipeWire, Bluetooth and the AGX Orin dev kit's single-output
  DisplayPort behaviour.
- [x] `R1-DESK-09` Adapt the Omarchy end-user and AArch64/Jetson skills to the
  installed command paths and prove their diagnostic examples.
- [x] `R1-DESK-10` Add a hardware power menu backed by the installed BSP's
  `nvpmodel` configuration, including current mode, CPU/GPU/EMC limits, fan
  policy, reboot requirements and explicit confirmation for mode changes.
- [x] `R1-DESK-12` Add a notification centre with user-closeable transient
  popups, configurable expiry, persistent unread history, a conditional bell,
  and read-all/mark-unread actions.
- [x] `R1-DESK-13` Make every top-bar module optional, use an icon or hidden
  state for audio, and support a disabled or auto-hidden bar revealed by a
  non-conflicting shortcut or pointer edge.
- [x] `R1-DESK-14` Add persistent user-named terminal work contexts with
  selectable coloured headers/accents, while retaining Foot and the upstream
  `Super+Enter` default-terminal shortcut.

## R1 — development environment

- [x] `R1-DEV-01` Install and validate Docker plus NVIDIA Container Toolkit
  with a pinned GPU-container known-answer case.
- [x] `R1-DEV-02` Install and validate VS Code AArch64, Python virtual
  environments, compilers, headers and selected common AI libraries.
- [x] `R1-DEV-03` Document native versus container dependency policy; reject
  accidental Ubuntu base/runtime dependencies.
- [ ] `R1-DEV-04` Validate 1Password CLI sign-in and secret references without
  exposing a secret in logs or process arguments.

## R1 — input, voice and capture

- [x] `R1-IN-01` Capture a desktop screenshot and control a focused application
  through the virtual keyboard/pointer layer, independent of USB HID.
- [x] `R1-IN-02` Pass a local Voxtype/Whisper known-audio transcription case.
- [x] `R1-IN-03` Provide push-to-talk dictation that types into the focused
  application like the keyboard; test cancel/interruption and failure recovery.

## R1 — hardware observability

- [x] `R1-OBS-01` Display CPU temperatures with sensor identity and failure state.
- [x] `R1-OBS-02` Display NVMe temperature/health without touching eMMC.
- [x] `R1-OBS-03` Display Jetson GPU activity, clocks, power/thermal state and
  unified GPU/system-memory pressure with accurate labels.
- [x] `R1-OBS-04` Determine whether this BSP exposes a meaningful GPU thermal
  zone; show it only when verified, otherwise explain its absence.
- [x] `R1-OBS-05` Add bounded logs and a support bundle that redacts secrets and
  records architecture/BSP/package versions.

## R1 completion gate

- [ ] `R1-GATE-01` All preceding `R1` acceptance cases pass on AGX Orin 64 GB.
- [x] `R1-GATE-02` Cold boot, reboot, suspend/idle where supported, network loss
  and disk-pressure recovery tests pass.
- [ ] `R1-GATE-03` Documentation and recovery instructions are reproduced by a
  second clean operator/build host.
- [ ] `R1-GATE-04` No known blocking correctness, compatibility, safety,
  maintainability, performance, observability, testability or operational-fit
  defect remains.

## POST-R1

- [x] `POST-R1-PLUG-03` Run upstream Omarchy's shell on the signed native
  AArch64 Quickshell package as the sole bar, retaining the verified
  notification/lock/Polkit owners. Waybar was removed because upstream ships
  none; systemd restart is the recovery path.
- [ ] `POST-R1-DESK-01` Validate DisplayPort MST/dock multi-monitor behaviour
  and evaluate wireless display casting as a separate optional feature.
- [ ] `POST-R1-SEC-01` Threat-model voice input, browser, secrets, the package
  channel and update paths.
- [ ] `POST-R1-SEC-02` Complete supply-chain/SBOM, network exposure, sandbox,
  physical-access and recovery audits.
