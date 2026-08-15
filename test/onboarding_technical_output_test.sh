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
short_display=$(technical_report 'Find printers' 'lpinfo -v' 0 $'direct usb://printer\nnetwork ipp' 2>&1)
[[ "$short_display" == *'Check: Find printers'* ]]
[[ "$short_display" == *'[  OK  ] success'* ]]
[[ "$short_display" == *'direct usb://printer'* ]]
[[ -f "$technical_transcript" ]]
[[ "$(stat -c '%a' "$technical_transcript")" == 600 ]]
grep -Fq 'Command: lpinfo -v' "$technical_transcript"

technical_report 'Redaction' 'probe' 1 'password=not-for-the-log' >/dev/null 2>&1
if grep -Fq 'not-for-the-log' "$technical_transcript"; then
  exit 1
fi
grep -Fq 'password=[REDACTED]' "$technical_transcript"

long_output=$(for number in {1..60}; do printf 'line-%02d\n' "$number"; done)
failure_display=$(technical_report 'Install tools' 'apt-get install' 9 "$long_output" 2>&1)
[[ "$failure_display" == *'line-60'* ]]
[[ "$failure_display" != *'line-01'* ]]
grep -Fq 'line-01' "$technical_transcript"

TECHNICAL_VERBOSE=true
verbose_display=$(technical_report 'Verbose probe' 'scanimage -L' 0 "$long_output" 2>&1)
[[ "$verbose_display" == *'line-01'* ]]
[[ "$verbose_display" == *'line-60'* ]]

captured=''
technical_capture captured 'Capture command' 'printf result' bash -c 'printf result' >/dev/null 2>&1
[[ "$captured" == result ]]

state_from_capture=''
set_state_from_capture() {
  state_from_capture=retained
  printf 'state retained'
}
technical_capture captured 'Capture state' 'set state' set_state_from_capture >/dev/null 2>&1
[[ "$state_from_capture" == retained ]]

finished=$(technical_transcript_finish 2>&1)
[[ "$finished" == *"$technical_transcript"* ]]

# --- step_check / step_action / step_stream ---

TECHNICAL_VERBOSE=false
technical_transcript_start "$workspace" step-test

# step_line_open only prints a pending marker on a real terminal, since a non-terminal
# consumer (a pipe, a log file, this test's own command substitution) can never render the
# carriage-return overwrite that step_line_close relies on to replace it.
[[ -z "$(step_line_open 'Checking sudo access' 2>&1)" ]]

# step_line_close puts the status tag first, then the label, and a real terminal writes a
# leading carriage return so the tag overwrites the pending marker in place.
[[ "$(step_line_close 0 'Checking sudo access' 2>&1)" == '[  OK  ] Checking sudo access' ]]

# step_check/step_action/step_stream write their captured output through a nameref,
# which command substitution (running the call in a subshell) would silently lose.
# Redirecting to a file instead keeps the call in the current shell.
display_file="$workspace/display.log"

out=''
step_check out 'Checking sudo access' 'sudo -v' bash -c 'printf remote-output' 2>"$display_file"
check_display=$(<"$display_file")
[[ "$out" == remote-output ]]
[[ "$check_display" == *'Checking sudo access'* ]]
[[ "$check_display" == *'[  OK  ]'* ]]
[[ "$check_display" != *'Technical details'* ]]
grep -Fq 'Checking sudo access' "$technical_transcript"
grep -Fq 'remote-output' "$technical_transcript"

out=''
TECHNICAL_VERBOSE=true step_check out 'Checking sudo access verbosely' 'sudo -v' bash -c 'printf remote-output' 2>"$display_file"
TECHNICAL_VERBOSE=false
check_verbose_display=$(<"$display_file")
[[ "$check_verbose_display" == *'Technical details'* ]]

out=''
fail_status=0
step_check out 'Checking a failing thing' 'false-check' bash -c 'printf fail-output; exit 3' 2>"$display_file" || fail_status=$?
check_fail_display=$(<"$display_file")
[[ "$fail_status" == 3 ]]
[[ "$check_fail_display" == *'[FAILED]'* ]]
[[ "$check_fail_display" == *'Technical details'* ]]
[[ "$check_fail_display" == *'fail-output'* ]]

# A passing action is always visible: it is labelled as a state-changing operation and its
# captured raw output is shown. Checks remain compact unless they fail or verbose mode is set.
out=''
step_action out 'Restarting a service' 'systemctl restart demo' bash -c 'printf action-output' 2>"$display_file"
action_display=$(<"$display_file")
[[ "$action_display" == *'[  OK  ]'* ]]
[[ "$action_display" == *'Action: Restarting a service'* ]]
[[ "$action_display" != *'Check: Restarting a service'* ]]
[[ "$action_display" == *'action-output'* ]]
grep -Fq 'action-output' "$technical_transcript"

# CLI audit F19: a successful action with no output still always gets the Action: label and its
# [  OK  ] result line, but the six-line "Technical details" box (divider, Command:, Result:,
# "Output: (none)", divider) is skipped -- there's nothing in it, and unconditionally showing an
# empty box for every trivial action (e.g. `systemctl start cups.service`) trains the eye to skim
# past boxes right before the one that actually has something to say.
out=''
step_action out 'Starting a quiet service' 'systemctl start demo-quiet' bash -c 'exit 0' 2>"$display_file"
quiet_action_display=$(<"$display_file")
[[ "$quiet_action_display" == *'Action: Starting a quiet service'* ]]
[[ "$quiet_action_display" == *'[  OK  ]'* ]]
[[ "$quiet_action_display" != *'Technical details'* ]]

out=''
action_fail_status=0
step_action out 'Restarting a failing service' 'systemctl restart demo-fail' bash -c 'printf action-fail-output; exit 4' 2>"$display_file" || action_fail_status=$?
action_fail_display=$(<"$display_file")
[[ "$action_fail_status" == 4 ]]
[[ "$action_fail_display" == *'[FAILED]'* ]]
[[ "$action_fail_display" == *'Technical details'* ]]
[[ "$action_fail_display" == *'action-fail-output'* ]]

out=''
TECHNICAL_VERBOSE=true step_action out 'Restarting a service verbosely' 'systemctl restart demo' bash -c 'printf action-output' 2>"$display_file"
TECHNICAL_VERBOSE=false
action_verbose_display=$(<"$display_file")
[[ "$action_verbose_display" == *'Technical details'* ]]

stream_fixture() {
  printf 'line-one\n'
  printf 'password=hunter2\n'
  printf 'line-two\n'
}
out=''
step_stream out 'Installing discovery tools' 'apt-get install' stream_fixture >"$display_file" 2>&1
stream_display=$(<"$display_file")
[[ "$out" == *'line-one'* && "$out" == *'password=hunter2'* && "$out" == *'line-two'* ]]
[[ "$stream_display" == *'line-one'* ]]
[[ "$stream_display" == *'password=hunter2'* ]]
[[ "$stream_display" == *'Installing discovery tools'* ]]
[[ "$stream_display" == *'Action: Installing discovery tools'* ]]
[[ "$stream_display" == *'[  OK  ]'* ]]
grep -Fq 'line-one' "$technical_transcript"
grep -Fq 'password=[REDACTED]' "$technical_transcript"
if grep -Fq 'password=hunter2' "$technical_transcript"; then
  exit 1
fi

out=''
stream_fail_status=0
stream_fail_fixture() { printf 'stream-fail-output\n'; return 5; }
step_stream out 'Installing a failing tool' 'apt-get install fails' stream_fail_fixture >"$display_file" 2>&1 || stream_fail_status=$?
stream_fail_display=$(<"$display_file")
[[ "$stream_fail_status" == 5 ]]
[[ "$stream_fail_display" == *'[FAILED]'* ]]
[[ "$stream_fail_display" == *'Technical details'* ]]

# step_check_live must never redirect the wrapped command's stdout/stderr into a file or pipe (a
# captured or piped interactive prompt can defeat the terminal's own echo suppression and leak
# typed secrets). Its own stdout inherits whatever step_check_live's caller had, so live_fixture's
# 'live-output' reaches this test's own capture directly and inline, exactly as if unwrapped ---
# what must NOT happen is that output landing in the saved transcript or in a re-displayed
# technical block, which is where step_check/step_action/step_stream deliberately keep a copy.
live_fixture() { printf 'live-output'; }
step_check_live 'Verify Raspberry Pi administrator privileges' 'sudo -v' live_fixture >"$display_file" 2>&1
live_display=$(<"$display_file")
[[ "$live_display" == *'live-output'* ]]
[[ "$live_display" == *'Verify Raspberry Pi administrator privileges'* ]]
[[ "$live_display" == *'[  OK  ]'* ]]
grep -Fq 'not captured to protect entered credentials' "$technical_transcript"
if grep -Fq 'live-output' "$technical_transcript"; then
  exit 1
fi

live_fail_status=0
live_fail_fixture() { return 7; }
step_check_live 'Failing live check' 'false-live' live_fail_fixture >"$display_file" 2>&1 || live_fail_status=$?
live_fail_display=$(<"$display_file")
[[ "$live_fail_status" == 7 ]]
[[ "$live_fail_display" == *'[FAILED]'* ]]
[[ "$live_fail_display" == *'not captured to protect entered credentials'* ]]
