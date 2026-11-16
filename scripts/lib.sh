#!/usr/bin/env bash

set -euo pipefail

fail() {
  local message="$1"
  printf '::error title=AboutTheApp Action::%s\n' "$message" >&2
  exit 1
}

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    fail "Required input '$name' is empty."
  fi
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    fail "Required command '$name' is not available on this runner. Use a GitHub-hosted Ubuntu runner or install it first."
  fi
}

write_output() {
  local name="$1"
  local value="$2"
  local output_file="${GITHUB_OUTPUT:-}"
  if [ -z "$output_file" ]; then
    fail "GITHUB_OUTPUT is not set. This script must run inside GitHub Actions or a compatible test harness."
  fi
  printf '%s=%s\n' "$name" "$value" >> "$output_file"
}

# Multipart POST: endpoint, token, file part ("name=@path;type=...;filename=..."), then text fields as "name=value".
# Text fields use --form-string, so values starting with @ or < and values containing ;type= are sent literally.
# A further file part is passed among the fields with the prefix "file:".
post_form() {
  local endpoint="$1"
  local token="$2"
  local file_part="$3"
  shift 3
  local response_file
  local http_code
  local response
  local form_args=()
  local field

  require_command curl
  require_command jq
  for field in "$@"; do
    if [[ "$field" == file:* ]]; then
      form_args+=(--form "${field#file:}")
    else
      form_args+=(--form-string "$field")
    fi
  done
  form_args+=(--form "$file_part")
  response_file=$(mktemp)

  if ! http_code=$(curl --silent --show-error \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --request POST "$endpoint" \
    --header "Authorization: Bearer $token" \
    "${form_args[@]}"); then
    rm -f "$response_file"
    fail "Could not connect to the AboutTheApp API at '$endpoint'."
  fi

  response=$(<"$response_file")
  rm -f "$response_file"

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    response=$(printf '%s' "$response" | tr '\r\n' ' ' | cut -c1-2000)
    fail "API request to '$endpoint' failed with HTTP $http_code. Response: $response"
  fi

  if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
    fail "API request to '$endpoint' returned HTTP $http_code but the response was not valid JSON."
  fi

  printf '%s' "$response"
}

# Ecosystem of a project file by its name; empty when the name is not recognised.
detect_ecosystem() {
  local name
  name=$(basename -- "$1")
  case "$name" in
    package.json|package-lock.json) echo npm ;;
    *.csproj|*.fsproj|*.vbproj|packages.config|Directory.Packages.props|packages.lock.json) echo nuget ;;
    requirements*.txt|pyproject.toml|Pipfile|Pipfile.lock|poetry.lock|uv.lock|pdm.lock) echo python ;;
    composer.json|composer.lock) echo composer ;;
    Cargo.toml|Cargo.lock) echo cargo ;;
    go.mod) echo go ;;
    pubspec.yaml|pubspec.lock) echo pub ;;
    Podfile|Podfile.lock) echo cocoapods ;;
    Package.swift|Package.resolved|Cartfile|Cartfile.resolved) echo swift ;;
    pom.xml|*.gradle|*.gradle.kts|libs.versions.toml|gradle.lockfile) echo maven ;;
    *) echo "" ;;
  esac
}

post_json() {
  local endpoint="$1"
  local body="$2"
  local token="$3"
  local response_file
  local http_code
  local response

  require_command curl
  require_command jq
  response_file=$(mktemp)

  if ! http_code=$(curl --silent --show-error \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --request POST "$endpoint" \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data "$body"); then
    rm -f "$response_file"
    fail "Could not connect to the AboutTheApp API at '$endpoint'."
  fi

  response=$(<"$response_file")
  rm -f "$response_file"

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    response=$(printf '%s' "$response" | tr '\r\n' ' ' | cut -c1-2000)
    fail "API request to '$endpoint' failed with HTTP $http_code. Response: $response"
  fi

  if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
    fail "API request to '$endpoint' returned HTTP $http_code but the response was not valid JSON."
  fi

  printf '%s' "$response"
}
