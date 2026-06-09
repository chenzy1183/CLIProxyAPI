#!/bin/sh
# entrypoint.sh - Railway/Docker container startup script
#
# Applies environment variables to config.yaml before starting CLIProxyAPI.
# This allows Railway users to configure the application via environment
# variables without committing sensitive config files to the repository.

set -e

CONFIG_FILE="/CLIProxyAPI/config.yaml"
EXAMPLE_FILE="/CLIProxyAPI/config.example.yaml"

# Bootstrap config.yaml from the example template if it doesn't exist yet.
if [ ! -f "$CONFIG_FILE" ]; then
  if [ -f "$EXAMPLE_FILE" ]; then
    echo "[entrypoint] config.yaml not found, copying from config.example.yaml"
    cp "$EXAMPLE_FILE" "$CONFIG_FILE"
  else
    echo "[entrypoint] WARNING: neither config.yaml nor config.example.yaml found"
  fi
fi

# Apply the 'api-keys' environment variable.
# Accepts a comma-separated or newline-separated list of keys.
# Example Railway env var value: "sk-key1,sk-key2,sk-key3"
if [ -n "${api_keys:-}" ] || [ -n "${API_KEYS:-}" ]; then
  RAW_KEYS="${api_keys:-${API_KEYS}}"
  echo "[entrypoint] Applying api-keys from environment variable"

  # Build a YAML sequence from the comma/newline-separated key list.
  YAML_KEYS=""
  # Normalise separators: replace commas with newlines, then iterate.
  echo "$RAW_KEYS" | tr ',' '\n' | while IFS= read -r key; do
    key="$(echo "$key" | tr -d '[:space:]')"
    [ -z "$key" ] && continue
    YAML_KEYS="${YAML_KEYS}  - \"${key}\"\n"
    printf '  - "%s"\n' "$key"
  done | {
    # Collect the formatted lines.
    FORMATTED="$(cat)"
    if [ -n "$FORMATTED" ] && [ -f "$CONFIG_FILE" ]; then
      # Replace the entire api-keys block (key + all following list items).
      # Strategy: use awk to replace from the 'api-keys:' line through the
      # last consecutive '  - ' list item that follows it.
      awk -v keys="$FORMATTED" '
        /^api-keys:/ {
          print "api-keys:"
          print keys
          skip = 1
          next
        }
        skip && /^[[:space:]]*-[[:space:]]/ { next }
        { skip = 0; print }
      ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      echo "[entrypoint] api-keys updated in config.yaml"
    fi
  }
fi

# Apply PGSTORE_DSN if set (the Go application already reads this env var
# natively, but log it here for visibility).
if [ -n "${PGSTORE_DSN:-}" ] || [ -n "${pgstore_dsn:-}" ]; then
  echo "[entrypoint] PGSTORE_DSN detected — postgres token store will be used"
fi

echo "[entrypoint] Starting CLIProxyAPI..."
exec ./CLIProxyAPI "$@"
