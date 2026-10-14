
-- Displays live in ~/.config/hypr/monitors.lua (loaded below), as in stock
-- Omarchy. SUPER + / and SUPER + ALT + / step the scaling up and down.

-- Upstream Omarchy (package `omarchy`, aarch64 [omarchy] repo) lives in
-- /usr/share/omarchy; the menu and shell IPC wrappers resolve from OMARCHY_PATH.
hl.env("OMARCHY_PATH", "/usr/share/omarchy")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border = "rgba(7aa2f7ee)",
            inactive_border = "rgba(414868aa)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
        active_opacity = 1.0,
        inactive_opacity = 0.97,
        shadow = { enabled = false },
        blur = { enabled = false },
    },
    animations = { enabled = false },
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = { natural_scroll = true },
    },
    dwindle = { preserve_split = true },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        -- No primary selection: highlighting text must never copy it or
        -- overwrite the clipboard. Copy only with Super+C / Ctrl+C.
        middle_click_paste = false,
        -- As upstream looknfeel.lua: a window asking for attention (e.g. Brave
        -- opening a link clicked in 1Password) is focused, switching workspace.
        focus_on_activate = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("omarchy-jetson-appearance apply-saved")
    hl.exec_cmd("omarchy-notification-center start")
    hl.exec_cmd("systemctl --user start omarchy-jetson-shell.service")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("systemctl --user start omarchy-jetson-idle.service")
end)

-- Upstream Omarchy's binding tree, from the `omarchy` package. The
-- preinstalled application/web-app bundle is intentionally excluded from this
-- Jetson profile; core desktop, media, capture and voice bindings remain.
-- Upstream's libalpm hooks pause Hyprland reloads while pacman replaces these
-- files, so a reload mid-upgrade can't drop into emergency mode.
local omarchy_config_tree = "/usr/share/omarchy"
dofile(omarchy_config_tree .. "/default/hypr/bootstrap.lua")
package.path = omarchy_config_tree .. "/?.lua;" .. package.path
require("default.hypr.helpers")

-- Named terminal work contexts retain their selected accent when focused or
-- inactive. Foot also receives the same CSD hint for compositors that render it.
for class, colour in pairs({
    ["omarchy-terminal-ff2563eb"] = "rgb(2563eb)",
    ["omarchy-terminal-ff7c3aed"] = "rgb(7c3aed)",
    ["omarchy-terminal-ff059669"] = "rgb(059669)",
    ["omarchy-terminal-ffd97706"] = "rgb(d97706)",
    ["omarchy-terminal-ffdc2626"] = "rgb(dc2626)",
    ["omarchy-terminal-ff475569"] = "rgb(475569)",
}) do
    o.window("^" .. class .. "$", { border_color = colour .. " " .. colour })
end

omarchy_preinstalled_bindings = false

-- Gap fix (ARM64/Jetson vs upstream x86 Omarchy 4.0.1). The Jetson binding tree
-- ships no default/hypr/apps/ rules, so nothing ever stamps the "terminal" tag
-- on terminal windows. default.hypr.bindings.clipboard branches on exactly that
-- tag: with it, SUPER+C/V send the terminal-native chords (CTRL+Insert /
-- SHIFT+Insert); without it they send CTRL+C/CTRL+V, which inside a terminal
-- means SIGINT and verbatim-insert -- i.e. copy and paste silently do nothing.
-- This is a window rule, not a key binding: it adds no keys. The match is the
-- upstream pattern verbatim so a terminal is classified identically to x86.
o.window(
    "(Alacritty|kitty|com\\.mitchellh\\.ghostty|foot|org\\.codeberg\\.dnkl\\.foot|wezterm|org\\.omarchy\\..*|TUI\\..*)",
    { tag = "+terminal" }
)

require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("default.hypr.bindings.tiling")
-- Jetson extras on top of upstream's tiling keys (upstream: SUPER+W close,
-- SUPER+S / SUPER+ALT+S scratchpad). Previously shipped by
-- omarchy-jetson-bindings; the keys are unused upstream.
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())
o.bind("SUPER + grave", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
o.bind("SUPER + SHIFT + grave", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
require("default.hypr.bindings.utilities")
require("default.hypr.bindings.voxtype")
require("default.hypr.bindings.applications")

o.bind("SUPER + CTRL + F9", "Cancel dictation", "omarchy-voice-control cancel")

-- Display configuration (stock Omarchy layout). Loaded only if present so a
-- missing file can never break the session.
local monitors_file = os.getenv("HOME") .. "/.config/hypr/monitors.lua"
if (io.open(monitors_file, "r")) then dofile(monitors_file) end


