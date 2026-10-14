# Voice control

Omarchy Jetson uses the local Voxtype/Whisper service as a push-to-talk input
method. Speech is typed into the focused Wayland application through `wtype`;
it is not routed through a privileged intent service. Consequently, dictated
text and keyboard-entered text cross the same application and permission
boundaries.

## Controls

- `F9`: start or stop dictation, matching upstream Omarchy.
- `Super+Ctrl+X`: toggle dictation, matching upstream Omarchy.
- `Super+Ctrl+F9`: cancel the current recording without typing its result.
- `omarchy-voice-control status`: report service and recording state.
- `omarchy-voice-control doctor`: verify the service and safety settings.
- `omarchy-voice-control recover`: restart a failed service and wait until the
  model is ready. Cold model loading may take up to 60 seconds.

Automatic submission and smart automatic submission are disabled. Dictation
only populates the focused input; the user must submit it through the same UI
action as typed text. The user service selects the PipeWire capture device,
because the Jetson's ALSA `default` device is not stable across the KVM audio
and local audio endpoints.

## Diagnostics

Run:

```sh
omarchy-voice-control doctor
journalctl --user -u voxtype.service -n 100 --no-pager
```

The service log is local, bounded by journald policy, and identifies daemon
startup, capture-device or model-load failures. It does not log dictated text.
Use `cancel` when an unintended recording is active. Use `recover` after an
audio-device loss or daemon failure; repeated failure should be included in the
redacted support bundle (`omarchy-jetson-support`).
