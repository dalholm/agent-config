#!/usr/bin/env bash
set -euo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$hook_dir/../scripts/agent-safety.mjs" hook
