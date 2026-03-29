#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

# ── Lib resolution ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
if [[ ! -d "$LIB_DIR" ]]; then
  LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
fi

source "$LIB_DIR/config.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/packages.sh"
source "$LIB_DIR/search.sh"
source "$LIB_DIR/shell.sh"
source "$LIB_DIR/flake.sh"

# ── Usage ───────────────────────────────────────────────────────
usage() {
  cat >&2 <<EOF
nixdash $VERSION — TUI for managing Nix packages

Usage: nixdash <command> [options]

Commands:
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
    -h|--help|"")
      usage
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
