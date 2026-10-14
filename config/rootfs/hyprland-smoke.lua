-- Minimal first-session configuration for the Jetson graphics smoke test.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.config({
    animations = { enabled = false },
    decoration = {
        blur = { enabled = false },
        shadow = { enabled = false },
    },
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("foot")
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
end)

hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("foot"))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + E", hl.dsp.exit())
