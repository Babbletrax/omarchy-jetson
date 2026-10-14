# shellcheck shell=bash

# shellcheck disable=SC1091
[[ -r /etc/bash.bashrc ]] && source /etc/bash.bashrc
# shellcheck disable=SC1090
[[ -r ~/.bashrc ]] && source ~/.bashrc

__omarchy_terminal_context_title() {
  printf '\033]0;%s\007' "${OMARCHY_TERMINAL_CONTEXT_TITLE:-Terminal}"
}

declare -a PROMPT_COMMAND
PROMPT_COMMAND+=(__omarchy_terminal_context_title)
