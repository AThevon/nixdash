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
  echo "[stub] nixdash add-flake — not yet implemented" >&2
}

cmd_init() {
  echo "[stub] nixdash init — not yet implemented" >&2
}

cmd_config() {
  echo "[stub] nixdash config — not yet implemented" >&2
}
