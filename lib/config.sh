#!/usr/bin/env bash
# nixdash — configuration

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nixdash"
CONFIG_FILE="$CONFIG_DIR/config.toml"

# config_get KEY — read a value from config.toml
# Supports dotted keys: "section.key" reads key under [section]
# Returns empty string if not found.
config_get() {
  local raw_key="$1"
  [[ -f "$CONFIG_FILE" ]] || { echo ""; return 0; }

  local section="" key="$raw_key"
  if [[ "$raw_key" == *.* ]]; then
    section="${raw_key%%.*}"
    key="${raw_key#*.}"
  fi

  awk -v section="$section" -v key="$key" '
    BEGIN { current_section = ""; found = 0 }
    /^[[:space:]]*\[/ {
      gsub(/^[[:space:]]*\[|][[:space:]]*$/, "")
      current_section = $0
      next
    }
    current_section == section {
      split($0, parts, /[[:space:]]*=[[:space:]]*/)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[1])
      if (parts[1] == key) {
        val = $0
        sub(/^[^=]*=[[:space:]]*/, "", val)
        gsub(/^"|"$/, "", val)
        print val
        found = 1
        exit
      }
    }
    END { if (!found) print "" }
  ' "$CONFIG_FILE"
}

# config_set KEY VALUE — write or update a value in config.toml
# Supports dotted keys: "section.key" writes key under [section]
# Creates file, directory, and section as needed.
config_set() {
  local raw_key="$1" value="$2"

  [[ -d "$CONFIG_DIR" ]] || mkdir -p "$CONFIG_DIR"

  local section="" key="$raw_key"
  if [[ "$raw_key" == *.* ]]; then
    section="${raw_key%%.*}"
    key="${raw_key#*.}"
  fi

  # If file doesn't exist, create it
  if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -z "$section" ]]; then
      printf '%s = "%s"\n' "$key" "$value" > "$CONFIG_FILE"
    else
      printf '\n[%s]\n%s = "%s"\n' "$section" "$key" "$value" > "$CONFIG_FILE"
    fi
    return 0
  fi

  # Try to update existing key in the right section
  local tmpfile
  tmpfile="$(mktemp)"

  local updated
  updated=$(awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { current_section = ""; replaced = 0 }
    /^[[:space:]]*\[/ {
      sec = $0
      gsub(/^[[:space:]]*\[|][[:space:]]*$/, "", sec)
      current_section = sec
      print
      next
    }
    current_section == section && !replaced {
      split($0, parts, /[[:space:]]*=[[:space:]]*/)
      k = parts[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == key) {
        printf "%s = \"%s\"\n", key, value
        replaced = 1
        next
      }
    }
    { print }
    END { printf "%d", replaced }
  ' "$CONFIG_FILE")

  local was_replaced="${updated##*$'\n'}"
  local content="${updated%$'\n'*}"

  if [[ "$was_replaced" == "1" ]]; then
    printf '%s\n' "$content" > "$CONFIG_FILE"
  else
    # Key not found — append it
    if [[ -z "$section" ]]; then
      # Append at the top (before any section), find first section or EOF
      awk -v key="$key" -v value="$value" '
        BEGIN { inserted = 0 }
        /^[[:space:]]*\[/ && !inserted {
          printf "%s = \"%s\"\n\n", key, value
          inserted = 1
        }
        { print }
        END { if (!inserted) printf "%s = \"%s\"\n", key, value }
      ' "$CONFIG_FILE" > "$tmpfile"
      mv "$tmpfile" "$CONFIG_FILE"
    else
      # Check if section exists
      if grep -q "^\[${section}\]" "$CONFIG_FILE" 2>/dev/null; then
        # Append key after section header
        awk -v section="$section" -v key="$key" -v value="$value" '
          /^[[:space:]]*\[/ {
            sec = $0
            gsub(/^[[:space:]]*\[|][[:space:]]*$/, "", sec)
            if (sec == section) {
              print
              printf "%s = \"%s\"\n", key, value
              next
            }
          }
          { print }
        ' "$CONFIG_FILE" > "$tmpfile"
        mv "$tmpfile" "$CONFIG_FILE"
      else
        # Add new section at the end
        printf '\n[%s]\n%s = "%s"\n' "$section" "$key" "$value" >> "$CONFIG_FILE"
      fi
    fi
  fi

  rm -f "$tmpfile"
}

# config_is_initialized — returns 0 if packages_file and apply_command are set
config_is_initialized() {
  local pkgfile appcmd
  pkgfile="$(config_get "packages_file")"
  appcmd="$(config_get "apply_command")"
  [[ -n "$pkgfile" && -n "$appcmd" ]]
}

# config_ensure — exits with message if not initialized
config_ensure() {
  if ! config_is_initialized; then
    echo "nixdash n'est pas configuré. Lancez 'nixdash init' d'abord." >&2
    exit 1
  fi
}
