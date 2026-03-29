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

source "$LIB_DIR/config.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/packages.sh"
source "$LIB_DIR/search.sh"
source "$LIB_DIR/shell.sh"
source "$LIB_DIR/flake.sh"

# ── Hub ────────────────────────────────────────────────────────
cmd_hub() {
  # If not initialized, offer to run init
  if ! config_is_initialized; then
    echo -e "${COLOR_BOLD}nixdash${COLOR_RESET} n'est pas encore configuré." >&2
    if ui_confirm "Lancer la configuration initiale ?"; then
      cmd_init
      # Re-check after init
      config_is_initialized || return 0
    else
      return 0
    fi
  fi

  while true; do
    # Count packages
    _packages_parse
    local pkg_count=0
    if [[ -n "$_PACKAGES_CACHE" ]]; then
      pkg_count="$(echo "$_PACKAGES_CACHE" | wc -l)"
    fi

    local choice
    choice="$(ui_choose "nixdash" \
      "📦 Mes packages ($pkg_count)" \
      "🔍 Rechercher un package" \
      "🐚 Shell temporaire" \
      "📥 Ajouter un flake externe" \
      "⚙️  Configuration" \
      "❌ Quitter")" || return 0

    case "$choice" in
      "📦 Mes packages"*)
        cmd_list
        ;;
      "🔍 Rechercher"*)
        cmd_search
        ;;
      "🐚 Shell"*)
        cmd_shell
        ;;
      "📥 Ajouter"*)
        cmd_add_flake
        ;;
      "⚙️  Configuration"*)
        cmd_config
        ;;
      "❌ Quitter")
        return 0
        ;;
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
    *)
      echo "nixdash: unknown command '$cmd'" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
