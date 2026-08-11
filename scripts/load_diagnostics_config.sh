#!/usr/bin/env bash

# Loads only DIAGNOSTICS_ENDPOINT from a local key=value file.
# This file intentionally does not source/evaluate the config, so arbitrary
# shell code placed in the config cannot execute during a build.
#
# Usage:
#   load_diagnostics_config "/path/to/config/private.env" [required]
#
# On success, exports DIAGNOSTICS_ENDPOINT when configured. Missing config is
# allowed only when required is 0.

load_diagnostics_config() {
  local config_path="${1:?config path is required}"
  local required="${2:-0}"

  if [[ ! -f "$config_path" ]]; then
    if [[ "$required" == "1" ]]; then
      echo "Diagnostics config is missing: $config_path" >&2
      echo "Create it from config/private.env.example and keep it outside Git." >&2
      return 1
    fi
    echo "Diagnostics endpoint is not configured; report sending is disabled." >&2
    return 0
  fi

  local permissions
  if [[ "$(uname -s)" == "Darwin" ]]; then
    permissions="$(stat -f '%Lp' "$config_path")"
  else
    permissions="$(stat -c '%a' "$config_path")"
  fi
  case "$permissions" in
    600|400) ;;
    *)
      echo "Diagnostics config must be owner-only (chmod 600): $config_path" >&2
      echo "Current permissions: $permissions" >&2
      return 1
      ;;
  esac

  local endpoint
  endpoint="$(awk -F= '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 ~ /^[[:space:]]*DIAGNOSTICS_ENDPOINT[[:space:]]*$/ {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$config_path")"

  if [[ -z "$endpoint" ]]; then
    if [[ "$required" == "1" ]]; then
      echo "DIAGNOSTICS_ENDPOINT is missing in $config_path" >&2
      return 1
    fi
    echo "Diagnostics endpoint is not configured; report sending is disabled." >&2
    return 0
  fi

  # Keep the client contract strict: HTTPS, a host, no embedded credentials,
  # and no whitespace. The dashboard itself remains the only secret-bearing
  # component.
  if [[ ! "$endpoint" =~ ^https://[^/@[:space:]]+(/[^[:space:]]*)?$ ]]; then
    echo "DIAGNOSTICS_ENDPOINT must be an HTTPS URL without embedded credentials." >&2
    return 1
  fi

  export DIAGNOSTICS_ENDPOINT="$endpoint"
}
