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
app_base="http://127.0.0.1:$(<"$PORT_FILE")/app"
api_base="http://127.0.0.1:$(<"$PORT_FILE")/api/v1"

version_output="$TEMP_DIR/version-output"
ALIAS=example-product \
VERSION=1.2.3 \
TOKEN=test-token \
API_BASE="$api_base" \
CHANGELOG='- Added script test' \
VISIBILITY=public \
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

sbom_file="$TEMP_DIR/sbom.cdx.json"
printf '%s' '{"bomFormat":"CycloneDX","specVersion":"1.6","components":[]}' > "$sbom_file"
sbom_output="$TEMP_DIR/sbom-output"
ALIAS=example-product \
VERSION=1.2.3 \
TOKEN=test-token \
API_BASE="$api_base" \
SBOM_FILE="$sbom_file" \
SBOM_PART=backend \
GITHUB_OUTPUT="$sbom_output" \
  bash "$ROOT_DIR/scripts/add-sbom.sh"
grep -Fxq 'id=sbom-1' "$sbom_output"
jq -s -e '.[2].path == "/api/v1/integrations/sboms" and .[2].body.alias == "example-product" and .[2].body.version == "1.2.3" and .[2].body.part == "backend" and .[2].body.gzip == true' "$REQUEST_LOG" >/dev/null

# Values that curl --form would read as a file (@...) or as part options (;type=) must arrive literally.
ALIAS=example-product \
VERSION='@missing-file' \
TOKEN=test-token \
API_BASE="$api_base" \
SBOM_FILE="$sbom_file" \
SBOM_PART='ios;type=text/plain' \
GITHUB_OUTPUT="$sbom_output" \
  bash "$ROOT_DIR/scripts/add-sbom.sh"
jq -s -e '.[3].body.version == "@missing-file" and .[3].body.part == "ios;type=text/plain" and .[3].body.gzip == true' "$REQUEST_LOG" >/dev/null

printf '%s' '{"spdxVersion":"SPDX-2.3"}' > "$TEMP_DIR/spdx.json"
if ALIAS=example-product VERSION=1.2.3 TOKEN=test-token API_BASE="$api_base" SBOM_FILE="$TEMP_DIR/spdx.json" \
  GITHUB_OUTPUT="$TEMP_DIR/invalid-output" bash "$ROOT_DIR/scripts/add-sbom.sh"; then
  echo 'Expected a non-CycloneDX SBOM to fail.' >&2
  exit 1
fi

if SBOM_PART=backend bash "$ROOT_DIR/scripts/validate-report.sh"; then
  echo 'Expected sbom-part without sbom-file to fail.' >&2
  exit 1
fi

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

VERIFY_URL="$app_base/version.json" VERIFY_FIELD=.app.version VERSION=1.2.3 VERIFY_TIMEOUT=0 \
  bash "$ROOT_DIR/scripts/verify-deployment.sh"
VERIFY_URL="$app_base/version.txt" VERSION=1.2.3 VERIFY_TIMEOUT=0 \
  bash "$ROOT_DIR/scripts/verify-deployment.sh"
VERIFY_URL="$app_base/rollout.json" VERSION=1.2.3 VERIFY_TIMEOUT=10 VERIFY_INTERVAL=1 \
  bash "$ROOT_DIR/scripts/verify-deployment.sh"

if VERIFY_URL="$app_base/version.json" VERSION=1.2.3 VERIFY_TIMEOUT=0 \
  bash "$ROOT_DIR/scripts/verify-deployment.sh"; then
  echo 'Expected a missing version field to fail.' >&2
  exit 1
fi

if VERIFY_URL="$app_base/version.txt" VERSION=1.2.4 VERIFY_TIMEOUT=1 VERIFY_INTERVAL=1 \
  bash "$ROOT_DIR/scripts/verify-deployment.sh"; then
  echo 'Expected a different deployed version to fail.' >&2
  exit 1
fi

if VERIFY_URL="$app_base/missing" VERSION=1.2.3 VERIFY_TIMEOUT=0 \
  bash "$ROOT_DIR/scripts/verify-deployment.sh"; then
  echo 'Expected an unreachable verify-url to fail.' >&2
  exit 1
fi

if VERIFY_URL="$app_base/version.json" ENVIRONMENT='' CUSTOMER_ALIAS='' \
  bash "$ROOT_DIR/scripts/validate-report.sh"; then
  echo 'Expected verify-url without an installation to fail.' >&2
  exit 1
fi

jq -s -e 'length == 4' "$REQUEST_LOG" >/dev/null

echo 'Shared script integration tests passed.'
