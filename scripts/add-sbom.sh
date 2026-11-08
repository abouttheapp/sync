#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

alias_name=${ALIAS:-}
version=${VERSION:-}
token=${TOKEN:-}
api_base=${API_BASE:-https://aboutthe.app/api/v1}
sbom_file=${SBOM_FILE:-}
sbom_part=${SBOM_PART:-}

require_value alias "$alias_name"
require_value version "$version"
require_value token "$token"
require_value sbom-file "$sbom_file"
require_value api-base "$api_base"
require_command jq

if [ ! -f "$sbom_file" ]; then
  fail "SBOM file '$sbom_file' does not exist."
fi
if ! jq -e '.bomFormat == "CycloneDX"' "$sbom_file" >/dev/null 2>&1; then
  if ! gzip -t "$sbom_file" 2>/dev/null; then
    fail "SBOM file '$sbom_file' is not a CycloneDX JSON document."
  fi
fi

printf '::add-mask::%s\n' "$token"

# The API accepts up to 10 MB of uncompressed JSON; compressing keeps uploads small behind proxies.
upload_file=$(mktemp)
trap 'rm -f "$upload_file"' EXIT
if gzip -t "$sbom_file" 2>/dev/null; then
  cp "$sbom_file" "$upload_file"
else
  gzip -c "$sbom_file" > "$upload_file"
fi

response=$(post_form "${api_base%/}/integrations/sboms" "$token" \
  "file=@$upload_file;type=application/gzip;filename=sbom.cdx.json.gz" \
  "alias=$alias_name" \
  "version=$version" \
  "part=$sbom_part")
id=$(printf '%s' "$response" | jq -er '.id | strings | select(length > 0)') || fail "SBOM response does not contain a valid 'id'."
count=$(printf '%s' "$response" | jq -r '.componentCount // 0')
write_output id "$id"
printf 'Uploaded SBOM with %s components for %s %s%s.\n' "$count" "$alias_name" "$version" "${sbom_part:+ ($sbom_part)}"
