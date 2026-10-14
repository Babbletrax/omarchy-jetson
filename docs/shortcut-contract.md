# Omarchy shortcut compatibility contract

## Normative source

The authoritative bindings for this build are upstream Omarchy's own binding
modules, installed by the upstream `omarchy` package under
`/usr/share/omarchy/default/hypr/bindings/`:

- `applications.lua`
- `clipboard.lua`
- `media.lua`
- `tiling.lua`
- `utilities.lua`
- `voxtype.lua`

Those files, including generated workspace/panel/group ranges and conditional
preinstalled-application bindings, are the contract. This document deliberately
does not duplicate every line into a second table that can drift. An upstream
update is reviewed through its binding diff; any required Jetson command
overrides are ported and the compatibility test is rerun.

## High-visibility contract

| Action | Upstream shortcut |
|---|---|
| Terminal | `Super+Return` |
| Browser | `Super+Shift+Return` or `Super+Shift+B` |
| File manager | `Super+Shift+F` |
| Editor | `Super+Shift+N` |
| Omarchy menu | `Super+Space` |
| Applications menu | `Super+Alt+Space` |
| System menu | `Super+Escape` |
| Keybindings | `Super+K` |
| Display panel | `Super+Ctrl+D` |
| Hardware menu | `Super+Ctrl+H` |
| Activity | `Super+Ctrl+T` |
| Agent picker (upstream) | `Super+Shift+Ctrl+A` |
| Full screenshot/capture | `Print` |
| Capture menu | `Super+Ctrl+C` |
| Screen recording | `Alt+Print` |
| Colour picker | `Super+Print` |
| Screenshot OCR | `Super+Ctrl+Print` |
| Monitor scale up/down | `Super+/` / `Super+Alt+/` |
| Close window | `Super+W` or `Super+Q` |
| Float/tile | `Super+T` |
| Full screen | `Super+F` |
| Workspaces 1–10 | `Super+1` … `Super+0` |
| Move window to workspace | `Super+Shift+1` … `Super+Shift+0` |
| Next/previous workspace | `Super+Tab` / `Super+Shift+Tab` |
| Lock | `Super+Ctrl+L` |
| Dictation toggle | `Super+Ctrl+X` |
| Dictation push-to-talk | hold `F9` |

Upstream clipboard, media, tiling, group, scratchpad, notification, panel,
brightness and pointer bindings remain part of the contract even though they
are not repeated above.

## Porting rules

1. Preserve key and action semantics across x86-64 Omarchy and AArch64
   Omarchy Jetson. Package substitutions happen behind the Omarchy command,
   not in the user's muscle memory.
2. Separate bindings into three classes:
   - Core desktop actions keep the upstream key and remain visible. If an
     implementation is temporarily unavailable, show the reason and do not
     silently reuse its key.
   - Profile capabilities (for example Docker or an editor) use the
     upstream key when that capability is installed. Menus discover these at
     runtime and omit absent capabilities without treating them as errors.
   - Omitted bundled applications and web apps have neither a menu entry nor a
     live binding. Their upstream keys stay unclaimed for user extensions.
3. Jetson-only bindings must be non-conflicting and documented in a separate
   extension section in the keybindings menu.
4. User overrides remain possible and are layered after defaults.
5. CI compares the effective default binding/action pairs with the pinned
   upstream files. An intentional upstream-version difference requires a
   recorded compatibility waiver.

## Jetson implementation

`config/rootfs/hyprland.lua` loads the six upstream binding modules directly
from `/usr/share/omarchy`, provided by upstream Omarchy's `omarchy` package
(signed aarch64 `[omarchy]` repo); the static test requires every module. The
initial profile disables upstream's conditional preinstalled application/web-app
bundle; it does not reuse those keys. Jetson extensions, none of which shadow an
upstream key: `Super+Q` closes a window (upstream: `Super+W`); `` Super+` ``
and `` Super+Shift+` `` toggle and fill the scratchpad (upstream: `Super+S`,
`Super+Alt+S`). No upstream key is rebound; `Super+Shift+Ctrl+A` keeps
upstream's `omarchy-agent --pick`.

The target validation on 2026-09-03 used Hyprland 0.56.1's real parser, reloaded
the live compositor with no config errors, and enumerated 211 effective binds.
It confirmed universal paste on `Super+V`, floating/tiling on `Super+T`, capture
menu on `Super+Ctrl+C`, screenshot on `Print`, and no enabled email/Maps
collision. Runtime implementations for menu/capture actions are tracked
separately from the now-stable key/action contract.

The initial Jetson profile intentionally does not install Omarchy's complete
application bundle. Terminal, browser, capture, window/workspace control and
the menu keys are core. Docker, editor and later plugin entries are
capabilities. Consumer web apps, music clients and messaging applications
are omitted unless a deployment profile or the user explicitly selects them.
