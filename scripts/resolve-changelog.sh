#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

source_name=${CHANGELOG_SOURCE:-none}
direct_text=${CHANGELOG:-}
since=${CHANGELOG_SINCE:-}
file=${CHANGELOG_FILE:-CHANGELOG.md}
version=${VERSION:-}
text=""

if [ -n "$direct_text" ] && [ "$source_name" != "none" ]; then
  fail "Input 'changelog' cannot be combined with changelog-source '$source_name'."
fi

case "$source_name" in
  none)
    text=$(printf '%s' "$direct_text")
    ;;
  git-log)
    require_command git
    if [ -n "$since" ]; then
      if ! git cat-file -e "${since}^{commit}" 2>/dev/null; then
        fail "Changelog start ref '$since' does not exist in the checked-out repository."
      fi
      text=$(git log --no-merges "${since}..HEAD" --pretty=format:'- %s')
    fi
    ;;
  file)
    require_value version "$version"
    if [ ! -f "$file" ]; then
      fail "Changelog file '$file' does not exist."
    fi
    text=$(awk -v version="$version" '
      function heading_version(line, closing, parts) {
        sub(/^##[[:space:]]+/, "", line)
        if (substr(line, 1, 1) == "[") {
          closing = index(line, "]")
          return closing > 2 ? substr(line, 2, closing - 2) : ""
        }
        split(line, parts, /[[:space:]]+/)
        return parts[1]
      }
      /^##[[:space:]]+/ {
        if (found) exit
        if (heading_version($0) == version) {
          found = 1
          next
        }
      }
      found { print }
      END { if (!found) exit 4 }
    ' "$file") || fail "Version '$version' was not found in changelog file '$file'."
    ;;
  *)
    fail "Unsupported changelog-source '$source_name'. Use none, git-log or file."
    ;;
esac

output_file=${GITHUB_OUTPUT:-}
if [ -z "$output_file" ]; then
  fail "GITHUB_OUTPUT is not set."
fi

delimiter="abouttheapp_changelog_${RANDOM}_$$"
while printf '%s\n' "$text" | grep -Fqx "$delimiter"; do
  delimiter="abouttheapp_changelog_${RANDOM}_$$"
done

{
  printf 'text<<%s\n' "$delimiter"
  printf '%s\n' "$text"
  printf '%s\n' "$delimiter"
} >> "$output_file"
