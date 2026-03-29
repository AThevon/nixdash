#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

# ── Lib resolution ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
if [[ ! -d "$LIB_DIR" ]]; then
  # Nix store layout: $out/bin/nixdash + $out/lib/nixdash/*.sh
  LIB_DIR="$(dirname "$SCRIPT_DIR")/lib/nixdash"
fi

ASSETS_DIR="$SCRIPT_DIR/assets"
if [[ ! -d "$ASSETS_DIR" ]]; then
  # Nix store layout: $out/bin/nixdash + $out/assets/nixdash/
  ASSETS_DIR="$(dirname "$SCRIPT_DIR")/assets/nixdash"
fi

# Resolve own binary path (for fzf --preview subprocesses)
NIXDASH_BIN="$(command -v nixdash 2>/dev/null || echo "$SCRIPT_DIR/nixdash.sh")"

source "$LIB_DIR/config.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/packages.sh"
source "$LIB_DIR/search.sh"
source "$LIB_DIR/shell.sh"
source "$LIB_DIR/flake.sh"

# ── Hub preview (called as subprocess by fzf) ─────────────────
_hub_preview() {
  local key="$1"
  case "$key" in
    list)
      echo -e "${COLOR_VIOLET}◈${COLOR_RESET}  My packages"
      echo ""
      echo "Displays all packages installed in your"
      echo "Nix configuration with an fzf interface."
      echo ""
      echo "• nixpkgs, flake inputs, conditional packages"
      echo "• Preview with description and version"
      echo "• Actions: remove, view online"
      ;;
    search)
      echo -e "${COLOR_VIOLET}⊕${COLOR_RESET}  Search packages"
      echo ""
      echo "Real-time search in nixpkgs via"
      echo "nix-search-tv with fuzzy matching."
      echo ""
      echo "• ✓ indicator for already installed packages"
      echo "• Selection → install to your config"
      echo "• Preview: description, version, homepage"
      ;;
    shell)
      echo -e "${COLOR_VIOLET}»${COLOR_RESET}  Temporary shell"
      echo ""
      echo "Creates a temporary Nix shell with the"
      echo "packages of your choice (multiselect)."
      echo ""
      echo "• Select multiple packages with TAB"
      echo "• Shell disappears on exit"
      echo "• No changes to your config"
      ;;
    add-flake)
      echo -e "${COLOR_VIOLET}⊞${COLOR_RESET}  Add external flake"
      echo ""
      echo "Guided workflow to add an external flake"
      echo "input to your configuration."
      echo ""
      echo "• Automatic URL resolution"
      echo "• Edits flake.nix + packages.nix"
      echo "• Preview changes before applying"
      ;;
    config)
      echo -e "${COLOR_DIM}⚙${COLOR_RESET}  Settings"
      echo ""
      echo "Edit nixdash settings:"
      echo ""
      echo "• Packages file"
      echo "• Apply command"
      echo "• Flake file"
      echo "• Toggle auto apply"
      echo "• Update nix-search-tv index"
      ;;
  esac
}

# ── Hub ────────────────────────────────────────────────────────
cmd_hub() {
  # If not initialized, offer to run init
  if ! config_is_initialized; then
    echo -e "${COLOR_BOLD}nixdash${COLOR_RESET} is not configured yet." >&2
    if ui_confirm "Run initial setup?"; then
      cmd_init
      config_is_initialized || return 0
    else
      return 0
    fi
  fi

  print_logo

  local nixdash_bin="$NIXDASH_BIN"

  # Build styled header
  local header
  header="$(printf '\033[1;38;5;135mnixdash\033[0m \033[2mv%s\033[0m │ \033[2mESC quit\033[0m' "$VERSION")"

  while true; do
    # Count packages
    _packages_parse
    local pkg_count=0
    if [[ -n "$_PACKAGES_CACHE" ]]; then
      pkg_count="$(echo "$_PACKAGES_CACHE" | grep -c '.' || true)"
    fi

    local tmpfile
    tmpfile="$(mktemp)"

    printf '%s\n' \
      "list     │ ${COLOR_VIOLET}◈${COLOR_RESET}  My packages ($pkg_count)" \
      "search   │ ${COLOR_VIOLET}⊕${COLOR_RESET}  Search packages" \
      "shell    │ ${COLOR_VIOLET}»${COLOR_RESET}  Temporary shell" \
      "add-flake│ ${COLOR_VIOLET}⊞${COLOR_RESET}  Add external flake" \
      "config   │ ${COLOR_DIM}⚙${COLOR_RESET}  Settings" \
    | fzf \
      --ansi \
      --no-sort \
      --height=50% \
      --layout=reverse \
      --border \
      --header "$header" \
      --preview "bash '$nixdash_bin' _hub-preview {1}" \
      --preview-window "right:50%:wrap" \
      --delimiter "│" \
      --with-nth 2.. \
    > "$tmpfile" || { rm -f "$tmpfile"; return 0; }

    local choice
    choice="$(cat "$tmpfile")"
    rm -f "$tmpfile"

    local cmd
    cmd="$(echo "$choice" | awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')"

    # Launch commands as subprocesses to get a clean TTY
    case "$cmd" in
      list)      "$NIXDASH_BIN" list ;;
      search)    "$NIXDASH_BIN" search ;;
      shell)     "$NIXDASH_BIN" shell ;;
      add-flake) "$NIXDASH_BIN" add-flake ;;
      config)    "$NIXDASH_BIN" config ;;
    esac
  done
}

# ── Usage ───────────────────────────────────────────────────────
usage() {
  cat >&2 <<EOF
nixdash $VERSION — TUI for managing Nix packages

Usage: nixdash <command> [options]

Commands:
  hub         Interactive menu (default)
  list        List installed packages
  search      Search for packages
  shell       Enter a temporary shell with packages
  add-flake   Add a flake input
  config      Edit nixdash configuration
  init        Initialize nixdash in a project

Options:
  -h, --help      Show this help
  -v, --version   Show version
EOF
}

# ── Command routing ─────────────────────────────────────────────
main() {
  local cmd="${1:-}"

  case "$cmd" in
    -v|--version)
      echo "nixdash $VERSION"
      ;;
    -h|--help)
      usage
      ;;
    ""|hub)
      cmd_hub
      ;;
    list)
      shift; cmd_list "$@"
      ;;
    search)
      shift; cmd_search "$@"
      ;;
    shell)
      shift; cmd_shell "$@"
      ;;
    add-flake)
      shift; cmd_add_flake "$@"
      ;;
    config)
      shift; cmd_config "$@"
      ;;
    init)
      shift; cmd_init "$@"
      ;;
    _search-preview)
      shift; _search_preview "$@"
      ;;
    _hub-preview)
      shift; _hub_preview "$@"
      ;;
    _config-preview)
      shift; _config_preview "$@"
      ;;
    *)
      echo "nixdash: unknown command '$cmd'" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
