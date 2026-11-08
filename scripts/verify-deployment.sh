#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

verify_url=${VERIFY_URL:-}
version=${VERSION:-}
field=${VERIFY_FIELD:-.version}
timeout=${VERIFY_TIMEOUT:-300}
interval=${VERIFY_INTERVAL:-10}

require_value verify-url "$verify_url"
require_value version "$version"
require_value verify-field "$field"
require_command curl
require_command jq

if [[ ! "$verify_url" =~ ^https?:// ]]; then
  fail "Unsupported verify-url '$verify_url'. Use an http or https URL."
fi
if [[ ! "$timeout" =~ ^[0-9]+$ ]]; then
  fail "Unsupported verify-timeout '$timeout'. Use a whole number of seconds."
fi
if [[ ! "$interval" =~ ^[1-9][0-9]*$ ]]; then
  fail "Unsupported verify-interval '$interval'. Use a whole number of seconds greater than zero."
fi

# JSON body: value selected by verify-field. Any other body: its first line, trimmed.
read_reported_version() {
  local body="$1"
  local line
  if printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$body" | jq -r "($field) // empty | tostring" 2>/dev/null || true
    return
  fi
  line=${body%%$'\n'*}
  line=${line%$'\r'}
  line=${line#"${line%%[![:space:]]*}"}
  printf '%s' "${line%"${line##*[![:space:]]}"}"
}

deadline=$((SECONDS + timeout))
while :; do
  if body=$(curl --silent --show-error --fail --location --max-time 10 \
    --header 'Cache-Control: no-cache' "$verify_url" 2>&1); then
    reported=$(read_reported_version "$body")
    if [ "$reported" = "$version" ]; then
      printf 'Deployment at %s reports version %s.\n' "$verify_url" "$version"
      exit 0
    fi
    if [ -z "$reported" ]; then
      status="returns no version"
    else
      status="reports '$(printf '%s' "$reported" | cut -c1-100)'"
    fi
  else
    status="is not reachable: $(printf '%s' "$body" | tr '\r\n' ' ' | cut -c1-200)"
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    fail "Deployment at '$verify_url' does not report version '$version' within ${timeout}s; it $status. Nothing was recorded in AboutTheApp."
  fi
  printf 'Waiting for version %s at %s; it %s.\n' "$version" "$verify_url" "$status"
  sleep "$interval"
done
