# Omarchy menu migration review

Review date: 2026-09-04. A decision record, not a work list.

The pinned Omarchy menu ships 320 items whose actions call 164 `omarchy-*`
commands. This build packages a subset, so every entry now carries a generated
`when:` guard and hides while its command is absent (see
`scripts/generate-menu-extension.py`). Nothing below is broken: a hidden entry
means the command was never packaged, which is either something to migrate or
something this platform deliberately does not do. Only the second column is a
judgement; the counts are measured on the target.

Of 138 commands the menu wants and this build lacks, 136 exist in the pinned
upstream tree and could be packaged. Only `omarchy-emacs` and
`omarchy-webapp-handler` exist nowhere.

## Sections

| Section | Working | Total | Commands needed | Notes |
|---|---:|---:|---:|---|
| `install` | 1 | 74 | 38 | Installs apps, fonts, services and web apps from Arch/AUR. This build has its own signed package channel. |
| `setup` | 1 | 51 | 18 | Per-topic configuration: monitors, network, DNS, security, browsers, default agent, config editors. |
| `remove` | 0 | 46 | 25 | Uninstalls what Install added. Mirror of the above. |
| `trigger` | 11 | 33 | 19 | One-shot actions: capture, share, emoji, reminders, hardware toggles. |
| `update` | 1 | 22 | 18 | Updates Omarchy itself, firmware, packages, and restarts processes. |
| `style` | 2 | 15 | 8 | Theme, background, fonts, bar, screensaver, branding. |
| `learn` | 1 | 9 | 4 | Opens documentation and keybinding references in a browser. |
| `system` | 5 | 5 | 0 | Session and power control. |
| `about` | 0 | 1 | 1 | About screen. |

## What each section would cost to bring across

### `install` — 1/74 working, 38 commands missing

Installs apps, fonts, services and web apps from Arch/AUR. This build has its own signed package channel.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-launch-floating-terminal-with-presentation` | 56 | yes |
| `omarchy-install-dev-env` | 18 | yes |
| `omarchy-install-browser` | 6 | yes |
| `omarchy-install-font` | 6 | yes |
| `omarchy-install-and-launch` | 5 | yes |
| `omarchy-install-terminal` | 4 | yes |
| `omarchy-install-app` | 3 | yes |
| `omarchy-games-retro-install` | 1 | yes |
| `omarchy-install-ai-chatgpt` | 1 | yes |
| `omarchy-install-chromium-google-account` | 1 | yes |
| `omarchy-install-docker-dbs` | 1 | yes |
| `omarchy-install-editor-emacs` | 1 | yes |
| `omarchy-install-editor-helix` | 1 | yes |
| `omarchy-install-editor-vscode` | 1 | yes |
| `omarchy-install-editor-zed` | 1 | yes |
| `omarchy-install-gaming-battlenet` | 1 | yes |
| `omarchy-install-gaming-geforce-now` | 1 | yes |
| `omarchy-install-gaming-heroic` | 1 | yes |
| `omarchy-install-gaming-lutris` | 1 | yes |
| `omarchy-install-gaming-retroarch` | 1 | yes |
| `omarchy-install-gaming-steam` | 1 | yes |
| `omarchy-install-gaming-xbox-cloud` | 1 | yes |
| `omarchy-install-gaming-xbox-controllers` | 1 | yes |
| `omarchy-install-preinstalls` | 1 | yes |
| `omarchy-install-service-1password` | 1 | yes |
| `omarchy-install-service-dropbox` | 1 | yes |
| `omarchy-install-service-nordvpn` | 1 | yes |
| `omarchy-install-service-once` | 1 | yes |
| `omarchy-install-service-signal` | 1 | yes |
| `omarchy-install-service-spotify` | 1 | yes |
| `omarchy-install-service-tailscale` | 1 | yes |
| `omarchy-pkg-aur-install` | 1 | yes |
| `omarchy-pkg-install` | 1 | yes |
| `omarchy-theme-install` | 1 | yes |
| `omarchy-tui-install` | 1 | yes |
| `omarchy-voxtype-install` | 1 | yes |
| `omarchy-webapp-install` | 1 | yes |
| `omarchy-windows-vm` | 1 | yes |

### `setup` — 1/51 working, 18 commands missing

Per-topic configuration: monitors, network, DNS, security, browsers, default agent, config editors.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-default-agent` | 9 | yes |
| `omarchy-launch-floating-terminal-with-presentation` | 9 | yes |
| `omarchy-default-editor` | 8 | yes |
| `omarchy-default-browser` | 7 | yes |
| `omarchy-launch-config-editor` | 6 | yes |
| `omarchy-default-terminal` | 4 | yes |
| `omarchy-dns` | 4 | yes |
| `omarchy-menu-plugin` | 4 | yes |
| `omarchy-plugin-add` | 1 | yes |
| `omarchy-restart-hyprsunset` | 1 | yes |
| `omarchy-restart-xcompose` | 1 | yes |
| `omarchy-setup-direct-boot` | 1 | yes |
| `omarchy-setup-security-fido2` | 1 | yes |
| `omarchy-setup-security-fingerprint` | 1 | yes |
| `omarchy-setup-security-sshd` | 1 | yes |
| `omarchy-setup-security-sudoless-docker` | 1 | yes |
| `omarchy-sudo-passwordless` | 1 | yes |
| `omarchy-system-factory-reset` | 1 | yes |

### `remove` — 0/46 working, 25 commands missing

Uninstalls what Install added. Mirror of the above.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-launch-floating-terminal-with-presentation` | 42 | yes |
| `omarchy-remove-dev-env` | 18 | yes |
| `omarchy-remove-browser` | 6 | yes |
| `omarchy-pkg-remove` | 1 | yes |
| `omarchy-remove-gaming-battlenet` | 1 | yes |
| `omarchy-remove-gaming-geforce-now` | 1 | yes |
| `omarchy-remove-gaming-heroic` | 1 | yes |
| `omarchy-remove-gaming-lutris` | 1 | yes |
| `omarchy-remove-gaming-minecraft` | 1 | yes |
| `omarchy-remove-gaming-retroarch` | 1 | yes |
| `omarchy-remove-gaming-steam` | 1 | yes |
| `omarchy-remove-gaming-xbox-cloud` | 1 | yes |
| `omarchy-remove-gaming-xbox-controllers` | 1 | yes |
| `omarchy-remove-preinstalls` | 1 | yes |
| `omarchy-remove-security-fido2` | 1 | yes |
| `omarchy-remove-security-fingerprint` | 1 | yes |
| `omarchy-remove-security-sshd` | 1 | yes |
| `omarchy-remove-security-sudoless-docker` | 1 | yes |
| `omarchy-remove-service-dropbox` | 1 | yes |
| `omarchy-remove-service-tailscale` | 1 | yes |
| `omarchy-theme-remove` | 1 | yes |
| `omarchy-tui-remove` | 1 | yes |
| `omarchy-voxtype-remove` | 1 | yes |
| `omarchy-webapp-remove` | 1 | yes |
| `omarchy-windows-vm` | 1 | yes |

### `trigger` — 11/33 working, 19 commands missing

One-shot actions: capture, share, emoji, reminders, hardware toggles.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-menu-share` | 3 | yes |
| `omarchy-reminder` | 3 | yes |
| `omarchy-capture-qr` | 1 | yes |
| `omarchy-capture-screenrecording-with-webcam` | 1 | yes |
| `omarchy-hyprland-monitor-internal` | 1 | yes |
| `omarchy-hyprland-monitor-internal-mirror` | 1 | yes |
| `omarchy-hyprland-window-gaps-toggle` | 1 | yes |
| `omarchy-hyprland-window-single-square-aspect-toggle` | 1 | yes |
| `omarchy-hyprland-workspace-layout-toggle` | 1 | yes |
| `omarchy-launch-floating-terminal-with-presentation` | 1 | yes |
| `omarchy-menu-emoji` | 1 | yes |
| `omarchy-toggle-bar` | 1 | yes |
| `omarchy-toggle-crash-capture` | 1 | yes |
| `omarchy-toggle-hybrid-gpu` | 1 | yes |
| `omarchy-toggle-nightlight` | 1 | yes |
| `omarchy-toggle-notification-silencing` | 1 | yes |
| `omarchy-toggle-touchpad` | 1 | yes |
| `omarchy-toggle-touchscreen` | 1 | yes |
| `omarchy-transcode` | 1 | yes |

### `update` — 1/22 working, 18 commands missing

Updates Omarchy itself, firmware, packages, and restarts processes.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-launch-floating-terminal-with-presentation` | 19 | yes |
| `omarchy-channel-set` | 4 | yes |
| `omarchy-drive-password` | 1 | yes |
| `omarchy-menu-timezone` | 1 | yes |
| `omarchy-refresh-hyprland` | 1 | yes |
| `omarchy-refresh-hyprsunset` | 1 | yes |
| `omarchy-refresh-plymouth` | 1 | yes |
| `omarchy-refresh-shell` | 1 | yes |
| `omarchy-refresh-tmux` | 1 | yes |
| `omarchy-restart-audio` | 1 | yes |
| `omarchy-restart-bluetooth` | 1 | yes |
| `omarchy-restart-hyprsunset` | 1 | yes |
| `omarchy-restart-trackpad` | 1 | yes |
| `omarchy-restart-wifi` | 1 | yes |
| `omarchy-theme-update` | 1 | yes |
| `omarchy-update` | 1 | yes |
| `omarchy-update-firmware` | 1 | yes |
| `omarchy-update-time` | 1 | yes |

### `style` — 2/15 working, 8 commands missing

Theme, background, fonts, bar, screensaver, branding.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-bar` | 5 | yes |
| `omarchy-branding-about` | 3 | yes |
| `omarchy-branding-screensaver` | 3 | yes |
| `omarchy-launch-config-editor` | 1 | yes |
| `omarchy-launch-floating-terminal-with-presentation` | 1 | yes |
| `omarchy-plymouth-reset` | 1 | yes |
| `omarchy-plymouth-set-by-theme` | 1 | yes |
| `omarchy-plymouth-switcher` | 1 | yes |

### `learn` — 1/9 working, 4 commands missing

Opens documentation and keybinding references in a browser.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-launch-webapp` | 5 | yes |
| `omarchy-launch-discord-community` | 1 | yes |
| `omarchy-menu-herdr-keybindings` | 1 | yes |
| `omarchy-menu-tmux-keybindings` | 1 | yes |

### `about` — 0/1 working, 1 commands missing

About screen.

| Command | Entries it unblocks | In upstream tree |
|---|---:|---|
| `omarchy-launch-about` | 1 | yes |

## Decision

Mark each section keep / migrate / drop. Dropping means the entries stay hidden,
which is already the current behaviour and costs nothing. Migrating means
packaging the listed commands and their own dependency closures.

