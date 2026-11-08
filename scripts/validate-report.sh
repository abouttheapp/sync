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

if [ -z "$sbom_file" ] && [ -n "$sbom_part" ]; then
  fail "Input 'sbom-part' requires 'sbom-file'."
fi

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
