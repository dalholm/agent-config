#!/usr/bin/env bash
set -euo pipefail

if rg -n -i 'ponytail' AGENTS.md README.md install.sh uninstall.sh skills; then
  echo "Ponytail references remain in repository configuration" >&2
  exit 1
fi
