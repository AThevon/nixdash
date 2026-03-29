#!/usr/bin/env bash
# nixdash — flake management

# --- Flake parsing/editing functions ---

_flake_file() {
  config_get "flake_file"
}

# flake_list_inputs — list all input names from flake.nix (lines with .url)
flake_list_inputs() {
  local flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]*\)\.url[[:space:]]*=.*/\1/p' "$flake_file"
}

# flake_get_input_url NAME — extract the URL for a given input
flake_get_input_url() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  local url
  url=$(sed -n "s/^[[:space:]]*${name}\.url[[:space:]]*=[[:space:]]*\"\(.*\)\";/\1/p" "$flake_file")
  echo "$url"
}

# flake_find_inputs_end — find line number of closing }; of inputs block
flake_find_inputs_end() {
  local flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  awk '
    /inputs[[:space:]]*=/ { in_inputs = 1 }
    in_inputs && /^[[:space:]]*\};/ { print NR; exit }
  ' "$flake_file"
}

# flake_find_extra_special_args — find line number of extraSpecialArgs
flake_find_extra_special_args() {
  local flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  grep -n "extraSpecialArgs" "$flake_file" | head -1 | cut -d: -f1
}

# flake_add_input NAME URL — insert input lines before inputs block closing
flake_add_input() {
  local name="$1" url="$2" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  local end_line
  end_line="$(flake_find_inputs_end)"
  [[ -n "$end_line" ]] || return 1
  local insert_text="    ${name}.url = \"${url}\";\n    ${name}.inputs.nixpkgs.follows = \"nixpkgs\";"
  sed -i "${end_line}i\\${insert_text}" "$flake_file"
}

# flake_add_inherit NAME — add name to existing inherit line or create new one in extraSpecialArgs
flake_add_inherit() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  # Try to find an existing inherit line in extraSpecialArgs block
  if grep -q "inherit " "$flake_file"; then
    # Add the name to the existing inherit line
    sed -i "s/\(inherit[[:space:]]\+.*\);/\1 ${name};/" "$flake_file"
  else
    # Find extraSpecialArgs opening and add inherit after it
    local args_line
    args_line="$(flake_find_extra_special_args)"
    [[ -n "$args_line" ]] || return 1
    sed -i "$((args_line + 1))i\\          inherit ${name};" "$flake_file"
  fi
}

# _flake_add_output_arg NAME — add name to outputs function args
_flake_add_output_arg() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  # outputs = { self, nixpkgs, ..., ... }:
  # Insert before ", ... }:" or before "... }:"
  sed -i "s/\(outputs[[:space:]]*=[[:space:]]*{[^}]*\),\([[:space:]]*\.\.\.[[:space:]]*}/\1, ${name},\2/" "$flake_file"
}

# flake_remove_input NAME — remove URL, follows, inherit reference, and output arg
flake_remove_input() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1

  # Remove input.url and input.inputs.nixpkgs.follows lines
  sed -i "/^[[:space:]]*${name}\.url[[:space:]]*=/d" "$flake_file"
  sed -i "/^[[:space:]]*${name}\.inputs\./d" "$flake_file"

  # Remove from inherit line — handle both "inherit name;" and "inherit name other;"
  # Case 1: sole inherit → remove the whole line
  sed -i "/^[[:space:]]*inherit[[:space:]]\+${name}[[:space:]]*;/d" "$flake_file"
  # Case 2: first in list → "inherit name other..." → "inherit other..."
  sed -i "s/\(inherit[[:space:]]\+\)${name}[[:space:]]\+/\1/" "$flake_file"
  # Case 3: in the middle or end → "inherit other name..." → "inherit other..."
  sed -i "s/\(inherit[[:space:]]\+.*\)[[:space:]]\+${name}\([[:space:]]*;\)/\1\2/" "$flake_file"

  # Remove from outputs args
  sed -i "s/,\s*${name}\([[:space:]]*,\)/\1/g" "$flake_file"
  sed -i "s/,\s*${name}\([[:space:]]*,\s*\.\.\.\)/\1/g" "$flake_file"
}

# --- Command stubs ---

cmd_add_flake() {
  config_ensure

  # 1. Prompt URL
  local url
  url="$(ui_input "URL du flake (ex: github:user/repo)")" || return 0
  [[ -z "$url" ]] && { ui_error "URL requise"; return 1; }

  # 2. Validate with nix flake metadata
  if ! ui_spin "Validation du flake..." nix flake metadata "$url" --no-write-lock-file; then
    ui_error "Flake invalide ou inaccessible : $url"
    return 1
  fi
  ui_success "Flake valide"

  # 3. Prompt input name (auto-suggest from URL)
  local suggested_name
  suggested_name="${url##*/}"
  suggested_name="${suggested_name%%#*}"
  local input_name
  input_name="$(ui_input "Nom de l'input" "$suggested_name")" || return 0
  [[ -z "$input_name" ]] && { ui_error "Nom d'input requis"; return 1; }

  # 4. Prompt package attribute
  local default_attr="packages.\${system}.default"
  local pkg_attr
  pkg_attr="$(ui_input "Attribut du package" "$default_attr")" || return 0
  [[ -z "$pkg_attr" ]] && pkg_attr="$default_attr"

  # Full package reference for packages.nix
  local full_pkg="${input_name}.${pkg_attr}"

  # 5. Preview changes
  echo -e "\n${COLOR_BOLD}Résumé des modifications :${COLOR_RESET}" >&2
  echo -e "  ${COLOR_CYAN}Input :${COLOR_RESET} ${input_name}.url = \"${url}\"" >&2
  echo -e "  ${COLOR_CYAN}Output arg :${COLOR_RESET} ${input_name} ajouté aux outputs" >&2
  echo -e "  ${COLOR_CYAN}Inherit :${COLOR_RESET} ${input_name} ajouté à extraSpecialArgs" >&2
  echo -e "  ${COLOR_CYAN}Package :${COLOR_RESET} ${full_pkg} ajouté aux packages" >&2
  echo >&2

  # 6. Choose action
  local action
  action="$(ui_choose "$input_name :" \
    "⊕  Installer dans la config" \
    "»  Tester dans un shell d'abord" \
    "↩  Annuler")" || return 0

  case "$action" in
    *"Tester"*)
      ui_info "Lancement d'un shell temporaire avec $url..."
      ui_dim "Tapez 'exit' pour quitter le shell temporaire."
      nix shell "$url"
      return 0
      ;;
    *"Annuler")
      ui_warn "Annulé"
      return 0
      ;;
  esac

  # Continue with install...

  # 7. Check structure
  local flake_file
  flake_file="$(_flake_file)"
  local inputs_end
  inputs_end="$(flake_find_inputs_end)"
  local esa_line
  esa_line="$(flake_find_extra_special_args)"

  if [[ -z "$inputs_end" || -z "$esa_line" ]]; then
    ui_warn "Structure du flake.nix non reconnue automatiquement."
    echo -e "\n${COLOR_BOLD}Instructions manuelles :${COLOR_RESET}" >&2
    echo -e "  1. Ajouter dans inputs :" >&2
    echo -e "     ${COLOR_GREEN}${input_name}.url = \"${url}\";${COLOR_RESET}" >&2
    echo -e "     ${COLOR_GREEN}${input_name}.inputs.nixpkgs.follows = \"nixpkgs\";${COLOR_RESET}" >&2
    echo -e "  2. Ajouter ${COLOR_GREEN}${input_name}${COLOR_RESET} aux arguments de outputs" >&2
    echo -e "  3. Ajouter ${COLOR_GREEN}inherit ${input_name};${COLOR_RESET} dans extraSpecialArgs" >&2
    echo -e "  4. Ajouter ${COLOR_GREEN}${full_pkg}${COLOR_RESET} dans votre fichier packages" >&2
    return 0
  fi

  # 8. Apply changes
  local flake_backup pkg_backup
  flake_backup="$(mktemp)"
  cp "$flake_file" "$flake_backup"

  local pkg_file
  pkg_file="$(config_get "packages_file")"
  pkg_backup="$(mktemp)"
  cp "$pkg_file" "$pkg_backup"

  flake_add_input "$input_name" "$url"
  _flake_add_output_arg "$input_name"
  flake_add_inherit "$input_name"
  packages_add "$full_pkg"

  # 9. Show diffs
  ui_info "Modifications dans flake.nix :"
  ui_diff "$flake_backup" "$flake_file"
  ui_info "Modifications dans $(basename "$pkg_file") :"
  ui_diff "$pkg_backup" "$pkg_file"

  rm -f "$flake_backup" "$pkg_backup"

  # 10. Apply
  local skip_confirmation
  skip_confirmation="$(config_get "skip_confirmation")"

  if [[ "$skip_confirmation" == "true" ]]; then
    ui_info "Application automatique..."
  else
    if ! ui_confirm "Appliquer les changements ?"; then
      ui_warn "Modifications écrites mais non appliquées"
      return 0
    fi
  fi

  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Exécution : $apply_cmd"
  eval "$apply_cmd"
  ui_success "Flake ${input_name} ajouté et appliqué"
}

cmd_init() {
  # 1. Welcome
  echo -e "\n${COLOR_BOLD}Bienvenue dans nixdash !${COLOR_RESET}" >&2
  echo -e "${COLOR_DIM}Assistant de configuration initiale${COLOR_RESET}\n" >&2

  # 2. Detect flake.nix
  local flake_file=""
  local search_dirs=("$HOME/.dotfiles" "$HOME/nixos-config" "$HOME/.config/nixos" ".")
  for dir in "${search_dirs[@]}"; do
    if [[ -f "$dir/flake.nix" ]]; then
      flake_file="$(cd "$dir" && pwd)/flake.nix"
      break
    fi
  done

  # 3. Prompt flake file path
  if [[ -n "$flake_file" ]]; then
    ui_info "Fichier flake détecté : $flake_file"
  else
    ui_warn "Aucun flake.nix détecté automatiquement"
  fi
  flake_file="$(ui_input "Chemin du fichier flake.nix" "$flake_file")" || return 0
  [[ -z "$flake_file" ]] && { ui_error "Chemin du flake requis"; return 1; }

  if [[ ! -f "$flake_file" ]]; then
    ui_error "Fichier introuvable : $flake_file"
    return 1
  fi

  # 4. Detect packages file
  local flake_dir
  flake_dir="$(dirname "$flake_file")"
  local pkg_file=""

  # Try home.packages first
  local match
  match="$(grep -rl "home\.packages" "$flake_dir" --include="*.nix" 2>/dev/null | head -1)" || true
  if [[ -n "$match" ]]; then
    pkg_file="$match"
  else
    # 5. Try environment.systemPackages (NixOS)
    match="$(grep -rl "environment\.systemPackages" "$flake_dir" --include="*.nix" 2>/dev/null | head -1)" || true
    if [[ -n "$match" ]]; then
      pkg_file="$match"
    fi
  fi

  # 6. Prompt packages file path
  if [[ -n "$pkg_file" ]]; then
    ui_info "Fichier packages détecté : $pkg_file"
  else
    ui_warn "Aucun fichier packages détecté"
  fi
  pkg_file="$(ui_input "Chemin du fichier packages" "$pkg_file")" || return 0
  [[ -z "$pkg_file" ]] && { ui_error "Chemin du fichier packages requis"; return 1; }

  if [[ ! -f "$pkg_file" ]]; then
    ui_error "Fichier introuvable : $pkg_file"
    return 1
  fi

  # 7. Count packages
  local tmp_config_dir tmp_config_file
  tmp_config_dir="$(mktemp -d)"
  tmp_config_file="$tmp_config_dir/config.toml"
  # Temporarily set config to count packages
  local orig_config_dir="$CONFIG_DIR" orig_config_file="$CONFIG_FILE"
  CONFIG_DIR="$tmp_config_dir"
  CONFIG_FILE="$tmp_config_file"
  config_set "packages_file" "$pkg_file"
  config_set "flake_file" "$flake_file"
  config_set "apply_command" "echo placeholder"
  _packages_parse
  local pkg_count=0
  if [[ -n "$_PACKAGES_CACHE" ]]; then
    pkg_count="$(echo "$_PACKAGES_CACHE" | wc -l)"
  fi
  CONFIG_DIR="$orig_config_dir"
  CONFIG_FILE="$orig_config_file"
  rm -rf "$tmp_config_dir"
  ui_info "$pkg_count packages détectés"

  # 8. Detect apply command
  local apply_cmd=""
  if grep -q "home-manager\|homeManagerConfiguration\|homeConfigurations" "$flake_file" 2>/dev/null; then
    apply_cmd="home-manager switch --flake $(dirname "$flake_file")"
  elif grep -q "nixosConfigurations\|nixos-rebuild" "$flake_file" 2>/dev/null; then
    apply_cmd="sudo nixos-rebuild switch --flake $(dirname "$flake_file")"
  fi

  # 9. Prompt apply command
  if [[ -n "$apply_cmd" ]]; then
    ui_info "Commande d'apply détectée : $apply_cmd"
  else
    ui_warn "Commande d'apply non détectée"
  fi
  apply_cmd="$(ui_input "Commande d'apply" "$apply_cmd")" || return 0
  [[ -z "$apply_cmd" ]] && { ui_error "Commande d'apply requise"; return 1; }

  # 10. Auto apply = false
  local skip_confirmation="false"

  # 11. Analyze flake structure
  local structure_info=""
  # Temporarily configure to analyze
  local save_dir="$CONFIG_DIR" save_file="$CONFIG_FILE"
  local analysis_dir
  analysis_dir="$(mktemp -d)"
  CONFIG_DIR="$analysis_dir"
  CONFIG_FILE="$analysis_dir/config.toml"
  config_set "flake_file" "$flake_file"
  local inputs_end esa_line
  inputs_end="$(flake_find_inputs_end)" || true
  esa_line="$(flake_find_extra_special_args)" || true
  CONFIG_DIR="$save_dir"
  CONFIG_FILE="$save_file"
  rm -rf "$analysis_dir"

  if [[ -n "$inputs_end" && -n "$esa_line" ]]; then
    structure_info="complète"
    ui_success "Structure flake reconnue (inputs end: L${inputs_end}, extraSpecialArgs: L${esa_line})"
  else
    structure_info="partielle"
    ui_warn "Structure flake partiellement reconnue — add-flake montrera les instructions manuelles"
  fi

  # 12. Check nix-search-tv
  if command -v nix-search-tv &>/dev/null; then
    ui_success "nix-search-tv disponible"
  else
    ui_warn "nix-search-tv non trouvé — la recherche ne fonctionnera pas"
    ui_dim "Installez-le : nix profile install github:peterldowns/nix-search-tv"
  fi

  # 13. Save config
  config_set "flake_file" "$flake_file"
  config_set "packages_file" "$pkg_file"
  config_set "apply_command" "$apply_cmd"
  config_set "skip_confirmation" "$skip_confirmation"

  echo >&2
  ui_success "Configuration sauvegardée dans $CONFIG_FILE"
  echo -e "  ${COLOR_DIM}flake_file    = $flake_file${COLOR_RESET}" >&2
  echo -e "  ${COLOR_DIM}packages_file = $pkg_file${COLOR_RESET}" >&2
  echo -e "  ${COLOR_DIM}apply_command = $apply_cmd${COLOR_RESET}" >&2
  echo -e "  ${COLOR_DIM}skip_confirmation    = $skip_confirmation${COLOR_RESET}" >&2
  echo -e "\n${COLOR_GREEN}nixdash est prêt !${COLOR_RESET} Lancez ${COLOR_BOLD}nixdash${COLOR_RESET} pour commencer.\n" >&2
}

_config_preview() {
  local key="$1"
  case "$key" in
    packages_file)
      echo -e "${COLOR_VIOLET}▪${COLOR_RESET}  Fichier packages"
      echo ""
      echo "Chemin vers le fichier .nix contenant"
      echo "la liste home.packages."
      echo ""
      echo "nixdash lit et modifie ce fichier pour"
      echo "ajouter/supprimer des packages."
      ;;
    apply_command)
      echo -e "${COLOR_VIOLET}▸${COLOR_RESET}  Commande d'apply"
      echo ""
      echo "Commande exécutée après chaque modification"
      echo "de packages (ajout ou suppression)."
      echo ""
      echo "Exemples :"
      echo "  home-manager switch --flake ~/.dotfiles"
      echo "  sudo nixos-rebuild switch --flake ."
      ;;
    flake_file)
      echo -e "${COLOR_VIOLET}◈${COLOR_RESET}  Fichier flake"
      echo ""
      echo "Chemin vers flake.nix."
      echo ""
      echo "Utilisé pour ajouter des flake inputs"
      echo "et détecter les packages externes."
      ;;
    skip_confirmation)
      echo -e "${COLOR_GREEN}◉${COLOR_RESET}  Passer la confirmation"
      echo ""
      echo "Si activé, nixdash applique les changements"
      echo "immédiatement sans demander confirmation."
      echo ""
      echo "Si désactivé, un diff est affiché et une"
      echo "confirmation est demandée avant d'appliquer."
      ;;
    update_index)
      echo -e "${COLOR_VIOLET}↻${COLOR_RESET}  Mettre à jour l'index"
      echo ""
      echo "Télécharge la dernière version de l'index"
      echo "nix-search-tv pour la recherche de packages."
      echo ""
      echo "À faire régulièrement pour avoir les"
      echo "dernières versions de nixpkgs."
      ;;
    redetect)
      echo -e "${COLOR_VIOLET}⟳${COLOR_RESET}  Relancer la détection"
      echo ""
      echo "Relance l'assistant de configuration"
      echo "initiale (nixdash init)."
      echo ""
      echo "Utile si vous avez déplacé vos fichiers"
      echo "ou changé de configuration Nix."
      ;;
    back)
      echo "Retour au hub"
      ;;
  esac
}

cmd_config() {
  config_ensure

  local nixdash_bin="$NIXDASH_BIN"

  while true; do
    local pkg_file flake_file apply_cmd skip_confirmation
    pkg_file="$(config_get "packages_file")"
    flake_file="$(config_get "flake_file")"
    apply_cmd="$(config_get "apply_command")"
    skip_confirmation="$(config_get "skip_confirmation")"

    local auto_label="non"
    [[ "$skip_confirmation" == "true" ]] && auto_label="oui"

    local choice
    choice="$(printf '%s\n' \
      "packages_file │ ${COLOR_VIOLET}▪${COLOR_RESET}  Fichier packages : $pkg_file" \
      "apply_command │ ${COLOR_VIOLET}▸${COLOR_RESET}  Commande d'apply : $apply_cmd" \
      "flake_file    │ ${COLOR_VIOLET}◈${COLOR_RESET}  Fichier flake : $flake_file" \
      "skip_confirmation    │ ${COLOR_GREEN}◉${COLOR_RESET}  Passer la confirmation : $auto_label" \
      "update_index  │ ${COLOR_VIOLET}↻${COLOR_RESET}  Mettre à jour l'index nix-search-tv" \
      "redetect      │ ${COLOR_VIOLET}⟳${COLOR_RESET}  Relancer la détection (nixdash init)" \
      "back          │ ${COLOR_DIM}↩${COLOR_RESET}  Retour" \
    | fzf \
      --ansi \
      --no-sort \
      --height=50% \
      --layout=reverse \
      --border \
      --header "Configuration nixdash" \
      --preview "bash '$nixdash_bin' _config-preview {1}" \
      --preview-window "right:50%:wrap" \
      --delimiter "│" \
      --with-nth 2.. \
    )" || return 0

    local cmd
    cmd="$(echo "$choice" | awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')"

    case "$cmd" in
      packages_file)
        local new_val
        new_val="$(ui_input "Chemin du fichier packages" "$pkg_file")" || continue
        [[ -n "$new_val" ]] && config_set "packages_file" "$new_val"
        ui_success "Fichier packages mis à jour"
        ;;
      apply_command)
        local new_val
        new_val="$(ui_input "Commande d'apply" "$apply_cmd")" || continue
        [[ -n "$new_val" ]] && config_set "apply_command" "$new_val"
        ui_success "Commande d'apply mise à jour"
        ;;
      flake_file)
        local new_val
        new_val="$(ui_input "Chemin du fichier flake.nix" "$flake_file")" || continue
        [[ -n "$new_val" ]] && config_set "flake_file" "$new_val"
        ui_success "Fichier flake mis à jour"
        ;;
      skip_confirmation)
        if [[ "$skip_confirmation" == "true" ]]; then
          config_set "skip_confirmation" "false"
          ui_success "Confirmation réactivée"
        else
          config_set "skip_confirmation" "true"
          ui_success "Confirmation désactivée"
        fi
        ;;
      update_index)
        if command -v nix-search-tv &>/dev/null; then
          ui_spin "Mise à jour de l'index nix-search-tv..." nix-search-tv fetch
          ui_success "Index mis à jour"
        else
          ui_error "nix-search-tv n'est pas installé"
        fi
        ;;
      redetect)
        cmd_init
        return 0
        ;;
      back)
        return 0
        ;;
    esac
  done
}
