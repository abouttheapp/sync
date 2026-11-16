#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

customer_alias=${CUSTOMER_ALIAS:-}
environment=${ENVIRONMENT:-}
url=${URL:-}
location=${LOCATION:-}
visibility=${VISIBILITY:-}
is_primary=${IS_PRIMARY:-}
version_visibility=${VERSION_VISIBILITY:-}
verify_url=${VERIFY_URL:-}
sbom_file=${SBOM_FILE:-}
sbom_part=${SBOM_PART:-}
sync_components=${SYNC_COMPONENTS:-false}
components_visibility=${COMPONENTS_VISIBILITY:-}
dependencies_file=${DEPENDENCIES_FILE:-}
dependencies_lockfile=${DEPENDENCIES_LOCKFILE:-}
dependencies_ecosystem=${DEPENDENCIES_ECOSYSTEM:-}
dependencies_include_dev=${DEPENDENCIES_INCLUDE_DEV:-false}

if [ -z "$sbom_file" ] && [ -n "$sbom_part" ]; then
  fail "Input 'sbom-part' requires 'sbom-file'."
fi

case "$sync_components" in
  ""|true|false) ;;
  *) fail "Unsupported sync-components '$sync_components'. Use true or false." ;;
esac

case "$components_visibility" in
  ""|public|private) ;;
  *) fail "Unsupported components-visibility '$components_visibility'. Use public or private, or leave it empty." ;;
esac

if [ -z "$sbom_file" ] && [ "$sync_components" = true ]; then
  fail "Input 'sync-components' requires 'sbom-file'."
fi

if [ "$sync_components" = true ] && [ -n "$dependencies_file" ]; then
  fail "Use either 'sync-components' or 'dependencies-file' to update components, not both."
fi

if [ -n "$components_visibility" ] && [ "$sync_components" != true ] && [ -z "$dependencies_file" ]; then
  fail "Input 'components-visibility' requires 'sync-components' or 'dependencies-file'."
fi

if [ -z "$dependencies_file" ] && { [ -n "$dependencies_lockfile" ] || [ -n "$dependencies_ecosystem" ] || [ "$dependencies_include_dev" = true ]; }; then
  fail "Inputs 'dependencies-lockfile', 'dependencies-ecosystem' and 'dependencies-include-dev' require 'dependencies-file'."
fi

if [ -n "$dependencies_file" ] && [ ! -f "$dependencies_file" ]; then
  fail "Dependencies file '$dependencies_file' does not exist."
fi

if [ -n "$dependencies_lockfile" ] && [ ! -f "$dependencies_lockfile" ]; then
  fail "Dependencies lockfile '$dependencies_lockfile' does not exist."
fi

case "$dependencies_include_dev" in
  ""|true|false) ;;
  *) fail "Unsupported dependencies-include-dev '$dependencies_include_dev'. Use true or false." ;;
esac

if [ -n "$sbom_file" ] && [ ! -f "$sbom_file" ]; then
  fail "SBOM file '$sbom_file' does not exist. Generate it in an earlier step."
fi

if { [ -n "$customer_alias" ] && [ -z "$environment" ]; } || { [ -z "$customer_alias" ] && [ -n "$environment" ]; }; then
  fail "Inputs 'customer-alias' and 'environment' must either both be supplied or both be empty."
fi

if [ -z "$customer_alias" ] && { [ -n "$url" ] || [ -n "$location" ] || [ -n "$visibility" ] || [ -n "$is_primary" ] || [ -n "$verify_url" ]; }; then
  fail "Installation options require both 'customer-alias' and 'environment'."
fi

case "$version_visibility" in
  ""|public|private) ;;
  *) fail "Unsupported version-visibility '$version_visibility'. Use public or private, or leave it empty." ;;
esac

case "$visibility" in
  ""|public|private) ;;
  *) fail "Unsupported installation-visibility '$visibility'. Use public or private, or leave it empty." ;;
esac

case "$is_primary" in
  ""|true|false) ;;
  *) fail "Unsupported is-primary '$is_primary'. Use true or false, or leave it empty." ;;
esac
