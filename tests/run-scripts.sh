#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_DIR=$(mktemp -d)
PORT_FILE="$TEMP_DIR/port"
REQUEST_LOG="$TEMP_DIR/requests.jsonl"
MOCK_PID=""

cleanup() {
  if [ -n "$MOCK_PID" ]; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

export PORT_FILE REQUEST_LOG
node "$ROOT_DIR/tests/mock-server.mjs" &
MOCK_PID=$!

for _ in {1..50}; do
  if [ -s "$PORT_FILE" ]; then break; fi
  sleep 0.1
done
test -s "$PORT_FILE"
api_base="http://127.0.0.1:$(<"$PORT_FILE")/api/v1"

version_output="$TEMP_DIR/version-output"
ALIAS=example-product \
VERSION=1.2.3 \
TOKEN=test-token \
API_BASE="$api_base" \
CHANGELOG='- Added script test' \
GITHUB_OUTPUT="$version_output" \
  bash "$ROOT_DIR/scripts/add-version.sh"
grep -Fxq 'id=version-1' "$version_output"

installation_output="$TEMP_DIR/installation-output"
ALIAS=example-product \
CUSTOMER_ALIAS=example-customer \
ENVIRONMENT=production \
VERSION=1.2.3 \
TOKEN=test-token \
API_BASE="$api_base" \
URL=https://example.test \
LOCATION=EU-West \
VISIBILITY=public \
IS_PRIMARY=true \
GITHUB_OUTPUT="$installation_output" \
  bash "$ROOT_DIR/scripts/add-installation.sh"
grep -Fxq 'id=installation-1' "$installation_output"

jq -s -e 'length == 2' "$REQUEST_LOG" >/dev/null
jq -s -e '.[0].body.version == "1.2.3" and .[0].body.changelog == "- Added script test" and .[0].body.visibility == "public"' "$REQUEST_LOG" >/dev/null
jq -s -e '.[1].body.environment == "production" and .[1].body.isPrimary == true' "$REQUEST_LOG" >/dev/null

changelog_file="$TEMP_DIR/CHANGELOG.md"
printf '%s\n' \
  '# Changelog' \
  '' \
  '## [1.2.3] - 2026-08-29' \
  '' \
  '- Added file changelog test' \
  '' \
  '## [1.2.2] - 2026-08-28' \
  '' \
  '- Previous release' > "$changelog_file"

changelog_output="$TEMP_DIR/changelog-output"
CHANGELOG_SOURCE=file \
CHANGELOG_FILE="$changelog_file" \
VERSION=1.2.3 \
GITHUB_OUTPUT="$changelog_output" \
  bash "$ROOT_DIR/scripts/resolve-changelog.sh"
grep -Fq -- '- Added file changelog test' "$changelog_output"
if grep -Fq -- '- Previous release' "$changelog_output"; then
  echo 'Changelog extraction included the previous release.' >&2
  exit 1
fi

if CUSTOMER_ALIAS=example-customer ENVIRONMENT='' bash "$ROOT_DIR/scripts/validate-report.sh"; then
  echo 'Expected incomplete installation inputs to fail.' >&2
  exit 1
fi

if ALIAS=example-product CUSTOMER_ALIAS=example-customer ENVIRONMENT=production VERSION=1.2.3 \
  TOKEN=test-token API_BASE="$api_base" IS_PRIMARY=invalid GITHUB_OUTPUT="$TEMP_DIR/invalid-output" \
  bash "$ROOT_DIR/scripts/add-installation.sh"; then
  echo 'Expected invalid is-primary to fail.' >&2
  exit 1
fi

echo 'Shared script integration tests passed.'
