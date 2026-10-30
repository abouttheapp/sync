#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

alias_name=${ALIAS:-}
version=${VERSION:-}
token=${TOKEN:-}
api_base=${API_BASE:-https://aboutthe.app/api/v1}
changelog=${CHANGELOG:-}
visibility=${VISIBILITY:-}

require_value alias "$alias_name"
require_value version "$version"
require_value token "$token"
require_value api-base "$api_base"
require_command jq

case "$visibility" in
  ""|public|private) ;;
  *) fail "Unsupported visibility '$visibility'. Use public or private, or leave it empty." ;;
esac

printf '::add-mask::%s\n' "$token"

body=$(jq -n \
  --arg alias "$alias_name" \
  --arg version "$version" \
  --arg changelog "$changelog" \
  --arg visibility "$visibility" \
  '{alias: $alias, version: $version}
   + (if ($changelog | length) > 0 then {changelog: $changelog} else {} end)
   + (if ($visibility | length) > 0 then {visibility: $visibility} else {} end)')

response=$(post_json "${api_base%/}/integrations/versions" "$body" "$token")
id=$(printf '%s' "$response" | jq -er '.id | strings | select(length > 0)') || fail "Version response does not contain a valid 'id'."
write_output id "$id"
printf 'Registered version %s for product %s.\n' "$version" "$alias_name"
