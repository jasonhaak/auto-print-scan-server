#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# No command, non-interactive (no TTY on stdin) falls back to the static reference instead of
# hanging on an interactive prompt.
help_output=$("$root/start" </dev/null 2>&1)
[[ "$help_output" == *'setup'* && "$help_output" == *'onboard'* && "$help_output" == *'reconfigure'* \
  && "$help_output" == *'manage-devices'* && "$help_output" == *'qa'* ]]
[[ "$help_output" == *'shared LAN print and scan server'* ]]
[[ "$help_output" == *'Use case'* ]]
[[ "$help_output" == *'First time, no Pi commissioned yet'* ]]

# Explicit help request behaves the same way regardless of TTY.
explicit_help=$("$root/start" help </dev/null 2>&1)
[[ "$explicit_help" == "$help_output" ]]

# An unknown command prints the reference to stderr and exits 2, without executing anything.
set +e
unknown_output=$("$root/start" bogus </dev/null 2>&1)
unknown_status=$?
set -e
[[ "$unknown_status" -eq 2 ]]
[[ "$unknown_output" == *'Unknown command: bogus'* ]]

printf 'start_test.sh: all checks passed\n'
