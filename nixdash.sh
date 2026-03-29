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
      echo "📦  Mes packages"
      echo ""
      echo "Affiche tous les packages installés dans votre"
      echo "configuration Nix avec une interface fzf."
      echo ""
      echo "• Packages nixpkgs, flake inputs, conditionnels"
      echo "• Preview avec description et version"
      echo "• Actions : supprimer, voir en ligne"
      ;;
    search)
      echo "🔍  Rechercher un package"
      echo ""
      echo "Recherche en temps réel dans nixpkgs via"
      echo "nix-search-tv avec fuzzy matching."
      echo ""
      echo "• Indicateur ✓ pour les packages déjà installés"
      echo "• Sélection → install dans votre config"
      echo "• Preview : description, version, homepage"
      ;;
    shell)
      echo "🐚  Shell temporaire"
      echo ""
      echo "Crée un shell Nix temporaire avec les packages"
      echo "de votre choix (multiselect)."
      echo ""
      echo "• Sélectionnez plusieurs packages avec TAB"
      echo "• Le shell disparaît à la fermeture (exit)"
      echo "• Aucune modification de votre config"
      ;;
    add-flake)
      echo "📥  Ajouter un flake externe"
      echo ""
      echo "Workflow guidé pour ajouter un flake input"
      echo "externe à votre configuration."
      echo ""
      echo "• Résolution automatique de l'URL"
      echo "• Édite flake.nix + packages.nix"
      echo "• Preview des modifications avant apply"
      ;;
    config)
      echo "⚙️   Configuration"
      echo ""
      echo "Modifier les réglages de nixdash :"
      echo ""
      echo "• Fichier packages"
      echo "• Commande d'apply"
      echo "• Fichier flake"
      echo "• Toggle apply automatique"
      echo "• Mettre à jour l'index nix-search-tv"
      ;;
  esac
}

# ── Hub ────────────────────────────────────────────────────────
cmd_hub() {
  # If not initialized, offer to run init
  if ! config_is_initialized; then
    echo -e "${COLOR_BOLD}nixdash${COLOR_RESET} n'est pas encore configuré." >&2
    if ui_confirm "Lancer la configuration initiale ?"; then
      cmd_init
      config_is_initialized || return 0
    else
      return 0
    fi
  fi

  print_logo

  local nixdash_bin
  nixdash_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

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

    local choice
    choice="$(printf '%s\n' \
      "list     │ 📦  Mes packages ($pkg_count)" \
      "search   │ 🔍  Rechercher un package" \
      "shell    │ 🐚  Shell temporaire" \
      "add-flake│ 📥  Ajouter un flake externe" \
      "config   │ ⚙️   Configuration" \
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
    )" || return 0

    local cmd
    cmd="$(echo "$choice" | awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')"

    case "$cmd" in
      list)      cmd_list ;;
      search)    cmd_search ;;
      shell)     cmd_shell ;;
      add-flake) cmd_add_flake ;;
      config)    cmd_config ;;
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
