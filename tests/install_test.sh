#!/usr/bin/env bash
set -euo pipefail

test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
output="$(HOME="$test_home" ./install.sh --dry-run --no-bootstrap)"

grep -Fq "$test_home/.pi/agent/node_modules" <<<"$output" || {
  echo "install.sh does not link Pi extension dependencies into ~/.pi/agent" >&2
  exit 1
}
