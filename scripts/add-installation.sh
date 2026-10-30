#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

alias_name=${ALIAS:-}
customer_alias=${CUSTOMER_ALIAS:-}
environment=${ENVIRONMENT:-}
version=${VERSION:-}
token=${TOKEN:-}
api_base=${API_BASE:-https://aboutthe.app/api/v1}
url=${URL:-}
location=${LOCATION:-}
visibility=${VISIBILITY:-}
is_primary=${IS_PRIMARY:-}

require_value alias "$alias_name"
require_value customer-alias "$customer_alias"
require_value environment "$environment"
require_value version "$version"
require_value token "$token"
require_value api-base "$api_base"
require_command jq

case "$visibility" in
  ""|public|private) ;;
  *) fail "Unsupported visibility '$visibility'. Use public or private, or leave it empty." ;;
esac

case "$is_primary" in
  ""|true|false) ;;
  *) fail "Unsupported is-primary '$is_primary'. Use true or false, or leave it empty." ;;
esac

printf '::add-mask::%s\n' "$token"

body=$(jq -n \
  --arg alias "$alias_name" \
  --arg customerAlias "$customer_alias" \
  --arg environment "$environment" \
  --arg version "$version" \
  --arg url "$url" \
  --arg location "$location" \
  --arg visibility "$visibility" \
  --arg isPrimary "$is_primary" \
  '{alias: $alias, customerAlias: $customerAlias, environment: $environment, version: $version}
   + (if ($url | length) > 0 then {url: $url} else {} end)
   + (if ($location | length) > 0 then {location: $location} else {} end)
   + (if ($visibility | length) > 0 then {visibility: $visibility} else {} end)
   + (if ($isPrimary | length) > 0 then {isPrimary: ($isPrimary == "true")} else {} end)')

response=$(post_json "${api_base%/}/integrations/installations" "$body" "$token")
id=$(printf '%s' "$response" | jq -er '.id | strings | select(length > 0)') || fail "Installation response does not contain a valid 'id'."
write_output id "$id"
printf 'Recorded version %s for product %s in %s/%s.\n' "$version" "$alias_name" "$customer_alias" "$environment"
