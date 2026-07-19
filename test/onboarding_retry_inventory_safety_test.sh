#!/usr/bin/env bash
set -euo pipefail

# Driving scripts/onboard end-to-end needs a live SSH target and interactive answers to five
# wizard stages, so this is a structural assertion instead: the collection-install and
# commissioning retry loops (after the one-time inventory mv on to production) must never
# write to production inventory, its variables file or the backup directory. If a future retry
# branch adds a mv/rm/cp touching those paths, this test fails.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
onboard="$root/scripts/onboard"

extract_loop() {
  local start_pattern=$1
  awk -v start="$start_pattern" '
    $0 ~ start { capturing = 1 }
    capturing { print }
    capturing && /^done$/ { exit }
  ' "$onboard"
}

galaxy_loop=$(extract_loop "step_stream galaxy_output 'Install pinned Ansible collections'")
commissioning_loop=$(extract_loop "step_stream ansible_output 'Commission the Raspberry Pi with Ansible'")

[[ -n "$galaxy_loop" ]]
[[ -n "$commissioning_loop" ]]
[[ "$galaxy_loop" == *'done'* ]]
[[ "$commissioning_loop" == *'done'* ]]

for loop_name in galaxy_loop commissioning_loop; do
  loop_body=${!loop_name}
  if grep -Eq '(^|[^A-Za-z_])(mv|rm|cp)[[:space:]].*(\$inventory|\$variables|\$backups|hosts\.yml|print_servers\.yml)' <<<"$loop_body"; then
    printf '%s touches production inventory, variables or backups\n' "$loop_name" >&2
    exit 1
  fi
done

# The retry branches must instead recreate the SSH session explicitly.
[[ "$galaxy_loop" == *'ssh_session_cleanup'* ]]
[[ "$galaxy_loop" == *'ssh_session_open'* ]]
[[ "$commissioning_loop" == *'ssh_session_cleanup'* ]]
[[ "$commissioning_loop" == *'ssh_session_open'* ]]
