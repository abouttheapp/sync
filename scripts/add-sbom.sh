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
sync_components=${SYNC_COMPONENTS:-false}
components_visibility=${COMPONENTS_VISIBILITY:-}

require_value alias "$alias_name"
require_value version "$version"
require_value token "$token"
require_value sbom-file "$sbom_file"
require_value api-base "$api_base"
require_command jq

case "$sync_components" in
  ""|false) sync_components=false ;;
  true) ;;
  *) fail "Unsupported sync-components '$sync_components'. Use true or false." ;;
esac
case "$components_visibility" in
  ""|public|private) ;;
  *) fail "Unsupported components-visibility '$components_visibility'. Use public or private, or leave it empty." ;;
esac

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

fields=("alias=$alias_name" "version=$version" "part=$sbom_part" "syncComponents=$sync_components")
if [ -n "$components_visibility" ]; then
  fields+=("componentsVisibility=$components_visibility")
fi
response=$(post_form "${api_base%/}/integrations/sboms" "$token" \
  "file=@$upload_file;type=application/gzip;filename=sbom.cdx.json.gz" \
  "${fields[@]}")
id=$(printf '%s' "$response" | jq -er '.id | strings | select(length > 0)') || fail "SBOM response does not contain a valid 'id'."
count=$(printf '%s' "$response" | jq -r '.componentCount // 0')
write_output id "$id"
printf 'Uploaded SBOM with %s components for %s %s%s.\n' "$count" "$alias_name" "$version" "${sbom_part:+ ($sbom_part)}"

if [ "$sync_components" = true ]; then
  created=$(printf '%s' "$response" | jq -er '.components.created | numbers') || fail "SBOM response does not contain the component sync result."
  updated=$(printf '%s' "$response" | jq -r '.components.updated // 0')
  unchanged=$(printf '%s' "$response" | jq -r '.components.unchanged // 0')
  write_output components-created "$created"
  write_output components-updated "$updated"
  printf 'Product components: %s added, %s updated, %s unchanged.\n' "$created" "$updated" "$unchanged"
fi
