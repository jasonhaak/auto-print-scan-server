#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/technical-output.sh"

workspace=$(mktemp -d "${TMPDIR:-/tmp}/technical-output-test.XXXXXX")
cleanup() {
  local status=$?
  rm -rf "$workspace"
  exit "$status"
}
trap cleanup EXIT

TECHNICAL_VERBOSE=false
technical_transcript_start "$workspace" test
short_display=$(technical_report 'Find printers' 'lpinfo -v' 0 $'direct usb://printer\nnetwork ipp')
[[ "$short_display" == *'Check: Find printers'* ]]
[[ "$short_display" == *'[OK] success'* ]]
[[ "$short_display" == *'direct usb://printer'* ]]
[[ -f "$technical_transcript" ]]
[[ "$(stat -c '%a' "$technical_transcript")" == 600 ]]
grep -Fq 'Command: lpinfo -v' "$technical_transcript"

technical_report 'Redaction' 'probe' 1 'password=not-for-the-log' >/dev/null
if grep -Fq 'not-for-the-log' "$technical_transcript"; then
  exit 1
fi
grep -Fq 'password=[REDACTED]' "$technical_transcript"

long_output=$(for number in {1..60}; do printf 'line-%02d\n' "$number"; done)
failure_display=$(technical_report 'Install tools' 'apt-get install' 9 "$long_output")
[[ "$failure_display" == *'line-60'* ]]
[[ "$failure_display" != *'line-01'* ]]
grep -Fq 'line-01' "$technical_transcript"

TECHNICAL_VERBOSE=true
verbose_display=$(technical_report 'Verbose probe' 'scanimage -L' 0 "$long_output")
[[ "$verbose_display" == *'line-01'* ]]
[[ "$verbose_display" == *'line-60'* ]]

captured=''
technical_capture captured 'Capture command' 'printf result' bash -c 'printf result'
[[ "$captured" == result ]]

state_from_capture=''
set_state_from_capture() {
  state_from_capture=retained
  printf 'state retained'
}
technical_capture captured 'Capture state' 'set state' set_state_from_capture
[[ "$state_from_capture" == retained ]]

finished=$(technical_transcript_finish)
[[ "$finished" == *"$technical_transcript"* ]]
