#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set +e
blocked_output="$(
  node "$repo/scripts/agent-safety.mjs" check-command \
    --command "rm -rf /" 2>&1
)"
blocked_status=$?
set -e

if [ "$blocked_status" -ne 2 ]; then
  echo "catastrophic root deletion was not blocked" >&2
  exit 1
fi

grep -Fq "BLOCKED" <<<"$blocked_output" || {
  echo "the guard did not explain the block" >&2
  exit 1
}

for command in \
  "rm -r -f /" \
  "rm -f -r /" \
  "rm --force --recursive /" \
  "rm --recursive --force -- /" \
  "rm -rf -- /" \
  "rm -rf \"/\"" \
  "rm --no-preserve-root -rf /" \
  "rm -rf --no-preserve-root /" \
  "rm -rf //" \
  "sudo rm --recursive /" \
  "rm -rf ~" \
  "rm -rf ~/" \
  "rm -rf \$HOME" \
  "rm -rf \"\$HOME/\"" \
  "rm -rf \"\$HOME\"/" \
  "rm -rf \"\${HOME}\"/*" \
  "rm -rf /Users" \
  "rm -rf /Users/alice" \
  "rm -rf /Users/alice/*" \
  "rm -rf \"/Users/alice/\"" \
  "rm -rf /home" \
  "rm -rf /home/" \
  "rm -rf /home/alice" \
  "rm -rf /root" \
  "rm -rf /etc" \
  "rm --recursive \"/System/\"" \
  "rm -rf /Volumes/*" \
  "dd if=/dev/zero of=/dev/disk0 bs=1m" \
  "mkfs.ext4 /dev/sda1" \
  "diskutil eraseDisk APFS Empty /dev/disk2" \
  ":(){ :|:& };:" \
  "chmod -R 777 /" \
  "chown -R root /" \
  "find / -delete"; do
  set +e
  node "$repo/scripts/agent-safety.mjs" check-command \
    --command "$command" >/dev/null 2>&1
  status=$?
  set -e
  if [ "$status" -ne 2 ]; then
    echo "catastrophic command was not blocked: $command" >&2
    exit 1
  fi
done

set +e
hook_output="$(
  printf '%s' '{"tool_input":{"command":"rm -rf /"}}' |
    "$repo/hooks/deny-dangerous.sh" 2>&1
)"
hook_status=$?
set -e

if [ "$hook_status" -ne 2 ]; then
  echo "the real hook process did not block a catastrophic command" >&2
  exit 1
fi

grep -Fq "BLOCKED" <<<"$hook_output" || {
  echo "the real hook process did not explain its denial" >&2
  exit 1
}

for command in \
  "rm -rf node_modules" \
  "rm -rf /tmp/build-cache" \
  "git reset --hard" \
  "git push --force-with-lease" \
  "docker system prune -f" \
  "find . -name '*.log' -delete" \
  "chmod 777 ./script.sh" \
  "chown -R user ./build"; do
  if ! node "$repo/scripts/agent-safety.mjs" check-command \
      --command "$command" >/dev/null 2>&1; then
    echo "recoverable or separately user-gated command was blocked: $command" >&2
    exit 1
  fi
done
