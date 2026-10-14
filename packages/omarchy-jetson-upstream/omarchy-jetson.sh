# shellcheck shell=sh
# Jetson AGX Orin: hardware-specific Omarchy commands (screen recording via
# wf-recorder, the work-context terminal launcher, the screensaver effect
# picker) live in /usr/lib/omarchy-jetson/bin and must win over the upstream
# copies in /usr/bin and $OMARCHY_PATH/bin. Sourced by login shells from /etc/profile.d.
case ":$PATH:" in
  *":/usr/lib/omarchy-jetson/bin:"*) ;;
  *) PATH="/usr/lib/omarchy-jetson/bin${PATH:+:$PATH}" ;;
esac
export PATH
