#!/usr/bin/env bash
set -euo pipefail

# Driving scripts/onboard end-to-end needs a live SSH target and interactive answers to five
# wizard stages, so this is a structural assertion instead: the collection-install and
# commissioning retry loops (after the one-time inventory mv on to production) must never
# write to production inventory, its variables file or the backup directory. If a future retry
# branch adds a mv/rm/cp touching those paths, this test fails.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
onboard="$root/scripts/onboard"

# The confirmed production write must be a visible action delegated to the shared inventory
# writer, rather than hand-written cp/mv calls in the onboarding script.
write_block=$(awk '/Write confirmed production inventory/{capturing = 1} capturing {print} capturing && /--variables-document/{exit}' "$onboard")
[[ "$write_block" == *'step_action'* ]]
[[ "$write_block" == *'device_inventory.py write-initial'* ]]

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

# The legacy-driver-preparation temp inventory must carry a real .yml extension so Ansible's
# yaml inventory plugin recognises it. mktemp appends its random suffix after the whole
# template, so `mktemp "$inventory.XXXXXX"` produces a filename like hosts.yml.a1B2c3 -- no
# recognised extension -- which silently falls through to the ini plugin, fails to parse the
# leading `---` marker, and matches zero hosts while ansible-playbook still exits 0.
legacy_inventory_block=$(awk '
  /^if \[\[ " \$\{printer_drivers\[\*\]\} " == \*'"'"' package_profile '"'"'\* \]\]; then$/ { capturing = 1 }
  capturing { print }
  capturing && /^fi$/ { exit }
' "$onboard")
[[ -n "$legacy_inventory_block" ]]
if grep -Eq 'mktemp "\$inventory\.XXXXXX"' <<<"$legacy_inventory_block"; then
  printf 'legacy-driver temp inventory uses an extensionless mktemp pattern\n' >&2
  exit 1
fi
[[ "$legacy_inventory_block" == *'mktemp "${inventory%.yml}.XXXXXX.yml"'* ]]

workspace=$(mktemp -d "${TMPDIR:-/tmp}/onboarding-retry-inventory-safety-test.XXXXXX")
trap 'rm -rf "$workspace"' EXIT
inventory_path="$workspace/hosts.yml"
generated_tmp=$(mktemp "${inventory_path%.yml}.XXXXXX.yml")
printf '%s\n' '---' 'all:' '  children:' '    print_servers:' '      hosts:' '        print-server:' '          ansible_host: "192.0.2.10"' '          ansible_user: "admin"' '          ansible_become: true' >"$generated_tmp"
ansible_playbook="$root/.venv/bin/ansible-playbook"
[[ -x "$ansible_playbook" ]] || ansible_playbook=ansible-playbook
list_hosts_output=$("$ansible_playbook" -i "$generated_tmp" --list-hosts "$root/playbooks/prepare-printer-profile.yml" 2>&1)
[[ "$list_hosts_output" == *'hosts (1)'* && "$list_hosts_output" == *'print-server'* ]]
