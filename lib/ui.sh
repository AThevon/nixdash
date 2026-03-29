#!/usr/bin/env bash
# nixdash - ui module
# Gum wrappers and formatting helpers

# Colors
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_CYAN="\033[36m"
COLOR_DIM="\033[2m"
COLOR_BOLD="\033[1m"
COLOR_RESET="\033[0m"

ui_info() {
  echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $*" >&2
}

ui_success() {
  echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*" >&2
}

ui_warn() {
  echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $*" >&2
}

ui_error() {
  echo -e "${COLOR_RED}✗${COLOR_RESET} $*" >&2
}

ui_dim() {
  echo -e "${COLOR_DIM}$*${COLOR_RESET}" >&2
}

# Gum choose wrapper
ui_choose() {
  local header="$1"
  shift
  gum choose --header "$header" "$@"
}

# Gum confirm wrapper
ui_confirm() {
  gum confirm "$1"
}

# Gum input wrapper
ui_input() {
  local placeholder="${1:-}"
  local value="${2:-}"
  if [[ -n "$value" ]]; then
    gum input --placeholder "$placeholder" --value "$value"
  else
    gum input --placeholder "$placeholder"
  fi
}

# Gum spin wrapper
ui_spin() {
  local title="$1"
  shift
  gum spin --spinner dot --title "$title" -- "$@"
}

# Show a diff between two strings
ui_diff() {
  local old_file="$1"
  local new_file="$2"
  diff --color=always -u "$old_file" "$new_file" | tail -n +3 >&2 || true
}

# Open URL in browser (cross-platform)
ui_open_url() {
  local url="$1"
  if command -v xdg-open &>/dev/null; then
    xdg-open "$url"
  elif command -v open &>/dev/null; then
    open "$url"
  elif command -v wslview &>/dev/null; then
    wslview "$url"
  else
    ui_warn "Impossible d'ouvrir le navigateur. URL : $url"
  fi
}
