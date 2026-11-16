#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

alias_name=${ALIAS:-}
token=${TOKEN:-}
api_base=${API_BASE:-https://aboutthe.app/api/v1}
dependencies_file=${DEPENDENCIES_FILE:-}
dependencies_lockfile=${DEPENDENCIES_LOCKFILE:-}
ecosystem=${DEPENDENCIES_ECOSYSTEM:-}
include_dev=${DEPENDENCIES_INCLUDE_DEV:-false}
components_visibility=${COMPONENTS_VISIBILITY:-}

require_value alias "$alias_name"
require_value token "$token"
require_value dependencies-file "$dependencies_file"
require_value api-base "$api_base"
require_command jq

if [ ! -f "$dependencies_file" ]; then
  fail "Dependencies file '$dependencies_file' does not exist."
fi
if [ -n "$dependencies_lockfile" ] && [ ! -f "$dependencies_lockfile" ]; then
  fail "Dependencies lockfile '$dependencies_lockfile' does not exist."
fi

if [ -z "$ecosystem" ]; then
  ecosystem=$(detect_ecosystem "$dependencies_file")
  if [ -z "$ecosystem" ]; then
    fail "Cannot tell the ecosystem of '$dependencies_file'. Set dependencies-ecosystem."
  fi
fi
case "$ecosystem" in
  npm|nuget|python|composer|cargo|go|pub|cocoapods|swift|maven) ;;
  *) fail "Unsupported dependencies-ecosystem '$ecosystem'. Use npm, nuget, python, composer, cargo, go, pub, cocoapods, swift or maven." ;;
esac
case "$include_dev" in
  ""|false) include_dev=false ;;
  true) ;;
  *) fail "Unsupported dependencies-include-dev '$include_dev'. Use true or false." ;;
esac
case "$components_visibility" in
  ""|public|private) ;;
  *) fail "Unsupported components-visibility '$components_visibility'. Use public or private, or leave it empty." ;;
esac

printf '::add-mask::%s\n' "$token"

# Copies keep curl from reading ';' or ',' in a user-supplied path as part options.
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
cp "$dependencies_file" "$work_dir/manifest"
fields=("alias=$alias_name" "ecosystem=$ecosystem" "includeDev=$include_dev")
if [ -n "$components_visibility" ]; then
  fields+=("visibility=$components_visibility")
fi
if [ -n "$dependencies_lockfile" ]; then
  cp "$dependencies_lockfile" "$work_dir/lockfile"
  fields+=("file:lockfile=@$work_dir/lockfile;type=text/plain;filename=lockfile")
fi

response=$(post_form "${api_base%/}/integrations/components/resolve" "$token" \
  "manifest=@$work_dir/manifest;type=text/plain;filename=manifest" \
  "${fields[@]}")
created=$(printf '%s' "$response" | jq -er '.created | numbers') || fail "Components response does not contain 'created'."
updated=$(printf '%s' "$response" | jq -r '.updated // 0')
unchanged=$(printf '%s' "$response" | jq -r '.unchanged // 0')
count=$(printf '%s' "$response" | jq -r '.dependencies // 0')
write_output components-created "$created"
write_output components-updated "$updated"
printf 'Read %s %s dependencies from %s. Product components: %s added, %s updated, %s unchanged.\n' \
  "$count" "$ecosystem" "$dependencies_file" "$created" "$updated" "$unchanged"
