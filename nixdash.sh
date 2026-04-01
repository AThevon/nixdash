#!/usr/bin/env bash
set -euo pipefail

VERSION="0.2.0"

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
    install-shell)
      echo -e "${COLOR_GREEN}⊕${COLOR_RESET}  Install shell packages"
      echo ""
      echo "Install the packages from your current"
      echo "temporary nix shell into your config."
      echo ""
      echo "Packages: ${NIXDASH_SHELL_PKGS:-none}"
      ;;
  esac
}

# ── Install packages from active nix shell ─────────────────────
_cmd_install_shell_pkgs() {
  [[ -z "${NIXDASH_SHELL_PKGS:-}" ]] && { ui_warn "No shell packages detected"; return 0; }

  local pkgs=()
  read -ra pkgs <<< "$NIXDASH_SHELL_PKGS"

  ui_info "Packages from current shell:"
  for pkg in "${pkgs[@]}"; do
    echo -e "  ${COLOR_CYAN}•${COLOR_RESET} $pkg" >&2
  done
  echo >&2

  local pkg_file
  pkg_file="$(config_get "packages_file")"
  local backup
  backup="$(mktemp)"
  cp "$pkg_file" "$backup"

  local added=0
  for pkg in "${pkgs[@]}"; do
    if ! packages_is_installed "$pkg"; then
      packages_add "$pkg"
      ((added++))
    else
      ui_dim "  $pkg already installed, skipping" >&2
    fi
  done

  if [[ $added -eq 0 ]]; then
    ui_warn "All packages already installed"
    rm -f "$backup"
    return 0
  fi

  ui_diff "$backup" "$pkg_file"

  if ! ui_confirm "Install $added package(s)?"; then
    cp "$backup" "$pkg_file"
    _PACKAGES_CACHE=""
    ui_warn "Cancelled — file restored"
    rm -f "$backup"
    return 0
  fi

  rm -f "$backup"
  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Running: $apply_cmd"
  eval "$apply_cmd"
  ui_success "$added package(s) installed"
  return 10
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

    # Build menu items
    local menu_items=(
      "list     │ ${COLOR_VIOLET}◈${COLOR_RESET}  My packages ($pkg_count)"
      "search   │ ${COLOR_VIOLET}⊕${COLOR_RESET}  Search packages"
      "shell    │ ${COLOR_VIOLET}»${COLOR_RESET}  Temporary shell"
      "add-flake│ ${COLOR_VIOLET}⊞${COLOR_RESET}  Add external flake"
    )

    # If in a nix shell with tracked packages, offer to install them
    if [[ -n "${NIXDASH_SHELL_PKGS:-}" ]]; then
      menu_items+=("install-shell│ ${COLOR_GREEN}⊕${COLOR_RESET}  Install shell packages (${NIXDASH_SHELL_PKGS})")
    fi

    menu_items+=("config   │ ${COLOR_DIM}⚙${COLOR_RESET}  Settings")

    local footer="^L packages · ^S search · ^T shell · ^F flake"

    printf '%s\n' "${menu_items[@]}" \
    | fzf \
      --ansi \
      --no-sort \
      --height=50% \
      --layout=reverse \
      --border \
      --header "$header" \
      --footer "$footer" \
      --expect=ctrl-l,ctrl-s,ctrl-t,ctrl-f \
      --preview "bash '$nixdash_bin' _hub-preview {1}" \
      --preview-window "right:50%:wrap" \
      --delimiter "│" \
      --with-nth 2.. \
    > "$tmpfile" || { rm -f "$tmpfile"; return 0; }

    local key
    key="$(head -1 "$tmpfile")"
    local choice
    choice="$(tail -n +2 "$tmpfile")"
    rm -f "$tmpfile"

    local cmd
    case "$key" in
      ctrl-l) cmd="list" ;;
      ctrl-s) cmd="search" ;;
      ctrl-t) cmd="shell" ;;
      ctrl-f) cmd="add-flake" ;;
      *)
        cmd="$(echo "$choice" | awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')"
        ;;
    esac

    # Commands that modify packages return 10 on success to signal hub exit
    local rc=0
    case "$cmd" in
      list)          cmd_list || rc=$? ;;
      search)        cmd_search || rc=$? ;;
      shell)         cmd_shell || true ;;
      add-flake)     cmd_add_flake || rc=$? ;;
      config)        cmd_config || true ;;
      install-shell) _cmd_install_shell_pkgs || rc=$? ;;
    esac
    [[ $rc -eq 10 ]] && return 0
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
    _list-preview)
      shift; _list_preview "$@"
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
