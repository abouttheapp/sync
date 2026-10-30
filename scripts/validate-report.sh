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

if { [ -n "$customer_alias" ] && [ -z "$environment" ]; } || { [ -z "$customer_alias" ] && [ -n "$environment" ]; }; then
  fail "Inputs 'customer-alias' and 'environment' must either both be supplied or both be empty."
fi

if [ -z "$customer_alias" ] && { [ -n "$url" ] || [ -n "$location" ] || [ -n "$visibility" ] || [ -n "$is_primary" ]; }; then
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
