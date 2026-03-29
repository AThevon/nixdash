#!/usr/bin/env bash
# nixdash - ui module
# Gum wrappers and formatting helpers

# ── Brand color: violet ────────────────────────────────────────
NIXDASH_COLOR="#8B5CF6"             # hex for gum
COLOR_VIOLET=$'\033[38;5;135m'      # ANSI 256-color violet

# Colors (use $'...' so escape codes are real bytes, not literal strings)
COLOR_GREEN=$'\033[32m'
COLOR_RED=$'\033[31m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'
COLOR_CYAN=$'\033[36m'
COLOR_DIM=$'\033[2m'
COLOR_BOLD=$'\033[1m'
COLOR_RESET=$'\033[0m'

# ── Logo ──────────────────────────────────────────────────────
print_logo() {
  [[ -n "${ASSETS_DIR:-}" && -f "$ASSETS_DIR/logo.ansi" ]] || return 0
  echo -e "$(cat "$ASSETS_DIR/logo.ansi")" >&2
}

ui_info() {
  echo -e "${COLOR_VIOLET}ℹ${COLOR_RESET} $*" >&2
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

# Gum choose wrapper (violet themed)
ui_choose() {
  local header="$1"
  shift
  gum choose \
    --header "$header" \
    --header.foreground "$NIXDASH_COLOR" \
    --cursor.foreground "$NIXDASH_COLOR" \
    --selected.foreground "$NIXDASH_COLOR" \
    "$@"
}

# Gum confirm wrapper (violet themed)
ui_confirm() {
  gum confirm \
    --selected.background "$NIXDASH_COLOR" \
    --selected.foreground "#fff" \
    --unselected.background "" \
    "$1"
}

# Gum input wrapper (violet themed)
ui_input() {
  local placeholder="${1:-}"
  local value="${2:-}"
  local args=(
    --placeholder "$placeholder"
    --cursor.foreground "$NIXDASH_COLOR"
    --prompt.foreground "$NIXDASH_COLOR"
  )
  if [[ -n "$value" ]]; then
    args+=(--value "$value")
  fi
  gum input "${args[@]}"
}

# Gum spin wrapper (violet themed)
ui_spin() {
  local title="$1"
  shift
  gum spin \
    --spinner dot \
    --spinner.foreground "$NIXDASH_COLOR" \
    --title "$title" \
    -- "$@"
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
