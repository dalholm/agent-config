#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT

mkdir -p "$test_home/.hermes/profiles/cloud"
printf 'cloud\n' > "$test_home/.hermes/active_profile"

HOME="$test_home" "$repo/install.sh" --no-bootstrap >/dev/null

coordinator_home="$test_home/.hermes/profiles/cloud"
test -L "$test_home/.hermes/skills/orca-development-orchestrator"
test -L "$coordinator_home/skills/orca-development-orchestrator"
test -L "$coordinator_home/skills/complexity-router"
test -L "$coordinator_home/skills/model-routing"
test -f "$coordinator_home/SOUL.md"

start_marker='<!-- agent-config:hermes-orca-coordinator:start -->'
end_marker='<!-- agent-config:hermes-orca-coordinator:end -->'
[ "$(grep -Fxc "$start_marker" "$coordinator_home/SOUL.md")" -eq 1 ]
[ "$(grep -Fxc "$end_marker" "$coordinator_home/SOUL.md")" -eq 1 ]
cmp -s "$repo/hermes/coordinator-soul.md" "$coordinator_home/SOUL.md"

idempotent_output="$(HOME="$test_home" "$repo/install.sh" --no-bootstrap)"
resolved_coordinator_home="$(cd "$coordinator_home" && pwd -P)"
grep -Fq "coordinator activation already current: $resolved_coordinator_home/SOUL.md" \
  <<<"$idempotent_output"
[ "$(find "$coordinator_home" -maxdepth 1 -name 'SOUL.md.bak-*' | wc -l | tr -d ' ')" -eq 0 ]

dry_run_home="$(mktemp -d)"
mkdir -p "$dry_run_home/.hermes/profiles/cloud"
printf 'cloud\n' > "$dry_run_home/.hermes/active_profile"
printf 'Dry-run personality.\n' > "$dry_run_home/.hermes/profiles/cloud/SOUL.md"
cp "$dry_run_home/.hermes/profiles/cloud/SOUL.md" "$dry_run_home/soul-before"

dry_run_output="$(HOME="$dry_run_home" "$repo/install.sh" --dry-run --no-bootstrap)"
dry_run_coordinator="$(cd "$dry_run_home/.hermes/profiles/cloud" && pwd -P)"
grep -Fq "would: back up $dry_run_coordinator/SOUL.md" <<<"$dry_run_output"
grep -Fq "would: install coordinator activation in $dry_run_coordinator/SOUL.md" <<<"$dry_run_output"
grep -Fq "(would link) $dry_run_coordinator/skills/orca-development-orchestrator" <<<"$dry_run_output"
cmp -s "$dry_run_home/soul-before" "$dry_run_home/.hermes/profiles/cloud/SOUL.md"
test ! -e "$dry_run_home/.hermes/profiles/cloud/skills"
test -z "$(find "$dry_run_home/.hermes/profiles/cloud" -maxdepth 1 -name 'SOUL.md.bak-*' -print -quit)"
rm -rf "$dry_run_home"

explicit_home="$(mktemp -d)"
mkdir -p "$explicit_home/.hermes/profiles/cloud"
printf 'cloud\n' > "$explicit_home/.hermes/active_profile"
HERMES_HOME="$explicit_home/coordinator" HOME="$explicit_home" \
  "$repo/install.sh" --no-bootstrap >/dev/null
test -f "$explicit_home/coordinator/SOUL.md"
test -L "$explicit_home/coordinator/skills/orca-development-orchestrator"
test ! -e "$explicit_home/.hermes/profiles/cloud/SOUL.md"
HERMES_HOME="$explicit_home/coordinator" HOME="$explicit_home" \
  "$repo/uninstall.sh" --keep-permissions >/dev/null
test ! -s "$explicit_home/coordinator/SOUL.md"
test ! -e "$explicit_home/coordinator/skills/orca-development-orchestrator"
rm -rf "$explicit_home"

fallback_home="$(mktemp -d)"
mkdir -p "$fallback_home/.hermes"
printf 'missing-profile\n' > "$fallback_home/.hermes/active_profile"
HOME="$fallback_home" "$repo/install.sh" --no-bootstrap >/dev/null
test -f "$fallback_home/.hermes/SOUL.md"
test ! -e "$fallback_home/.hermes/profiles/missing-profile/SOUL.md"
rm -rf "$fallback_home"

unsafe_profile_home="$(mktemp -d)"
mkdir -p "$unsafe_profile_home/.hermes/profiles"
printf '.\n' > "$unsafe_profile_home/.hermes/active_profile"
HOME="$unsafe_profile_home" "$repo/install.sh" --no-bootstrap >/dev/null
test -f "$unsafe_profile_home/.hermes/SOUL.md"
test ! -e "$unsafe_profile_home/.hermes/profiles/SOUL.md"
rm -rf "$unsafe_profile_home"

outside_home="$(mktemp -d)"
outside_target="$(mktemp -d)"
set +e
HERMES_HOME="$outside_target" HOME="$outside_home" \
  "$repo/install.sh" --dry-run --no-bootstrap >/dev/null 2>&1
outside_status=$?
set -e
[ "$outside_status" -ne 0 ]
test ! -e "$outside_target/SOUL.md"
rm -rf "$outside_home" "$outside_target"

replacement_home="$(mktemp -d)"
mkdir -p "$replacement_home/.hermes/profiles/cloud"
printf 'cloud\n' > "$replacement_home/.hermes/active_profile"
cat > "$replacement_home/.hermes/profiles/cloud/SOUL.md" <<'EOF'
Original personality.
<!-- agent-config:hermes-orca-coordinator:start -->
Old coordinator instructions.
<!-- agent-config:hermes-orca-coordinator:end -->
Unrelated tail.
EOF
cp "$replacement_home/.hermes/profiles/cloud/SOUL.md" "$replacement_home/soul-before"

HOME="$replacement_home" "$repo/install.sh" --no-bootstrap >/dev/null

replacement_coordinator="$replacement_home/.hermes/profiles/cloud"
replacement_backup="$(find "$replacement_coordinator" -maxdepth 1 -name 'SOUL.md.bak-*' -print -quit)"
test -n "$replacement_backup"
cmp -s "$replacement_home/soul-before" "$replacement_backup"
{
  printf 'Original personality.\n'
  cat "$repo/hermes/coordinator-soul.md"
  printf 'Unrelated tail.\n'
} > "$replacement_home/soul-expected"
cmp -s "$replacement_home/soul-expected" "$replacement_coordinator/SOUL.md"

replacement_backup_count="$(find "$replacement_coordinator" -maxdepth 1 -name 'SOUL.md.bak-*' | wc -l | tr -d ' ')"
HOME="$replacement_home" "$repo/install.sh" --no-bootstrap >/dev/null
[ "$(find "$replacement_coordinator" -maxdepth 1 -name 'SOUL.md.bak-*' | wc -l | tr -d ' ')" -eq "$replacement_backup_count" ]

cp "$replacement_coordinator/SOUL.md" "$replacement_home/soul-before-dry-uninstall"
dry_uninstall_output="$(HOME="$replacement_home" "$repo/uninstall.sh" --dry-run --keep-permissions)"
resolved_replacement_coordinator="$(cd "$replacement_coordinator" && pwd -P)"
grep -Fq "would: remove managed coordinator activation from $resolved_replacement_coordinator/SOUL.md" \
  <<<"$dry_uninstall_output"
cmp -s "$replacement_home/soul-before-dry-uninstall" "$replacement_coordinator/SOUL.md"
test -L "$replacement_coordinator/skills/orca-development-orchestrator"

ln -s /tmp "$replacement_coordinator/skills/unrelated-skill"
HOME="$replacement_home" "$repo/uninstall.sh" --keep-permissions >/dev/null

printf 'Original personality.\nUnrelated tail.\n' > "$replacement_home/soul-after-uninstall"
cmp -s "$replacement_home/soul-after-uninstall" "$replacement_coordinator/SOUL.md"
test -L "$replacement_coordinator/skills/unrelated-skill"
test ! -e "$replacement_coordinator/skills/orca-development-orchestrator"
test ! -e "$replacement_home/.hermes/skills/orca-development-orchestrator"
[ "$(find "$replacement_coordinator" -maxdepth 1 -name 'SOUL.md.bak-*' | wc -l | tr -d ' ')" -eq "$replacement_backup_count" ]

rm -rf "$replacement_home"
