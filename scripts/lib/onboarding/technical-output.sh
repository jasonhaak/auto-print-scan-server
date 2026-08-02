#!/usr/bin/env bash

technical_redact() {
  sed -E \
    -e 's/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt])([=:])[[:graph:]]+/\1\2[REDACTED]/g' \
    -e 's/([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*)[[:graph:]]+/\1[REDACTED]/g'
}

if ! declare -F cli_color >/dev/null; then
  cli_color() { printf '%s' "$2"; }
fi

cli_status() {
  local status=$1
  if [[ "$status" == 0 ]]; then
    cli_color '32' '[  OK  ]'
  else
    cli_color '31' '[FAILED]'
  fi
}

step_tag_text() {
  if [[ "$1" == 0 ]]; then printf '[  OK  ]'; else printf '[FAILED]'; fi
}

step_tag_colored() {
  if [[ "$1" == 0 ]]; then
    cli_color '32' '[  OK  ]'
  else
    cli_color '31' '[FAILED]'
  fi
}

# On a terminal, a pending marker is printed first and overwritten in place (via carriage
# return) once the outcome is known, so a slow step still shows it is in progress without
# printing the status tag before the status exists. Piped/non-terminal output skips the
# overwrite (it can't render one) and only prints the final line.
step_line_open() {
  if [[ -t 1 ]]; then
    printf '[ .... ] %s' "$1"
  fi
  return 0
}

step_line_close() {
  local status=$1 purpose=$2 prefix=''
  if [[ -t 1 ]]; then
    prefix=$'\r'
  fi
  printf '%s%s %s\n' "$prefix" "$(step_tag_colored "$status")" "$purpose"
}

step_line_full() {
  step_line_open "$1"
  step_line_close "$2" "$1"
}

technical_transcript_write() {
  local purpose=$1 command_label=$2 status=$3 raw_output=${4:-}
  local output
  output=$(printf '%s' "$raw_output" | technical_redact)
  {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$purpose"
    printf 'Command: %s\nStatus: %s\n' "$command_label" "$status"
    [[ -n "$output" ]] && printf 'Output:\n%s\n' "$output"
  } >>"$technical_transcript"
}

technical_block_print() {
  local purpose=$1 command_label=$2 status=$3 raw_output=${4:-}
  local output line_count
  output=$(printf '%s' "$raw_output" | technical_redact)
  printf '\n%s\n' "$(cli_color '1;36' '──────────────── Technical details ────────────────')"
  printf '%s %s\n' "$(cli_color '1;36' 'Check:')" "$purpose"
  printf '%s %s\n' 'Command:' "$command_label"
  printf '%s %s\n' 'Result:' "$(cli_status "$status") $([[ "$status" == 0 ]] && printf success || printf 'failed (exit %s)' "$status")"
  if [[ -n "$output" ]]; then
    line_count=$(printf '%s\n' "$output" | awk 'END { print NR }')
    printf '%s\n' 'Output:'
    if [[ "${TECHNICAL_VERBOSE:-false}" == true || "$line_count" -le 40 ]]; then
      printf '%s\n' "$output"
    elif [[ "$status" == 0 ]]; then
      printf '%s\n' "$output" | sed -n '1,20p'
      printf '... %d line(s) omitted; full output is in the transcript ...\n' "$((line_count - 30))"
      printf '%s\n' "$output" | tail -n 10
    else
      printf '... showing the final 40 of %d lines; full output is in the transcript ...\n' "$line_count"
      printf '%s\n' "$output" | tail -n 40
    fi
  else
    printf '%s\n' 'Output: (none)'
  fi
  printf '%s\n' "$(cli_color '1;36' '────────────────────────────────────────────────────')"
}

step_run() {
  local output_variable=$1 purpose=$2 command_label=$3
  local -n step_output_ref=$output_variable
  shift 3
  local output_file
  step_line_open "$purpose"
  output_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-step.XXXXXX")
  if "$@" >"$output_file" 2>&1; then step_run_status=0; else step_run_status=$?; fi
  step_run_output=$(<"$output_file")
  rm -f "$output_file"
  step_output_ref=$step_run_output
  step_line_close "$step_run_status" "$purpose"
  technical_transcript_write "$purpose" "$command_label" "$step_run_status" "$step_run_output"
}

step_check() {
  local output_variable=$1 purpose=$2 command_label=$3
  shift 3
  step_run "$output_variable" "$purpose" "$command_label" "$@"
  if [[ "$step_run_status" != 0 || "${TECHNICAL_VERBOSE:-false}" == true ]]; then
    technical_block_print "$purpose" "$command_label" "$step_run_status" "$step_run_output"
  fi
  return "$step_run_status"
}

# Actions differ from checks because they change inventory or Raspberry Pi state. Their label and
# captured technical output are always shown, while successful read-only checks stay compact.
step_action() {
  local output_variable=$1 purpose=$2 command_label=$3
  shift 3
  printf '%s %s\n' "$(cli_color '1;33' 'Action:')" "$purpose"
  step_run "$output_variable" "$purpose" "$command_label" "$@"
  technical_block_print "$purpose" "$command_label" "$step_run_status" "$step_run_output"
  return "$step_run_status"
}

# Like step_check, but never redirects the wrapped command's stdout/stderr. Use this only for a
# command that may interactively prompt for a secret (for example the first `sudo -v` of a run).
# Capturing such a prompt to a file or pipe (as step_check/step_action/step_stream do) can defeat
# the terminal's own echo suppression and leak typed characters into the technical block and the
# saved transcript. The transcript records that output was intentionally not captured instead.
#
# Unlike step_check, the label line ends with a newline before the command runs rather than
# staying open for an inline status tag: an uncaptured command can write straight to the
# terminal (a password prompt, an SSH "Shared connection ... closed" notice), and that live
# text must land below the label, not spliced into the middle of it. The status is then
# printed as its own "label ... [OK]" recap line once the command finishes, so the outcome is
# unambiguous even after several lines of interleaved chatter.
step_check_live() {
  local purpose=$1 command_label=$2 status placeholder
  shift 2
  placeholder='(interactive session; output not captured to protect entered credentials)'
  printf '%s ...\n' "$purpose"
  if "$@"; then status=0; else status=$?; fi
  step_line_full "$purpose" "$status"
  technical_transcript_write "$purpose" "$command_label" "$status" "$placeholder"
  if [[ "$status" != 0 || "${TECHNICAL_VERBOSE:-false}" == true ]]; then
    technical_block_print "$purpose" "$command_label" "$status" "$placeholder"
  fi
  return "$status"
}

step_stream() {
  local output_variable=$1 purpose=$2 command_label=$3
  local -n step_output_ref=$output_variable
  shift 3
  local output_file status output
  printf '%s ...\n' "$purpose"
  output_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-step.XXXXXX")
  if "$@" 2>&1 | tee "$output_file"; then
    status=0
  else
    status=${PIPESTATUS[0]}
  fi
  output=$(<"$output_file")
  rm -f "$output_file"
  step_output_ref=$output
  step_line_full "$purpose" "$status"
  technical_transcript_write "$purpose" "$command_label" "$status" "$output"
  [[ "$status" == 0 ]] || technical_block_print "$purpose" "$command_label" "$status" "$output"
  return "$status"
}

technical_transcript_start() {
  local project_root=$1 run_name=${2:-onboard} previous_umask stamp
  technical_log_directory="$project_root/.onboard-logs"
  mkdir -p "$technical_log_directory"
  chmod 700 "$technical_log_directory"
  stamp=$(date +%Y%m%d-%H%M%S)
  technical_transcript="$technical_log_directory/${run_name}-${stamp}-$$.log"
  previous_umask=$(umask)
  umask 077
  : >"$technical_transcript"
  umask "$previous_umask"
  chmod 600 "$technical_transcript"
  technical_transcript_finished=false
}

technical_report() {
  local purpose=$1 command_label=$2 status=$3 raw_output=${4:-}
  technical_transcript_write "$purpose" "$command_label" "$status" "$raw_output"
  technical_block_print "$purpose" "$command_label" "$status" "$raw_output"
}

technical_capture() {
  local output_variable=$1 purpose=$2 command_label=$3 output output_file status
  local -n captured_output=$output_variable
  shift 3
  output_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-technical.XXXXXX")
  if "$@" >"$output_file" 2>&1; then
    status=0
  else
    status=$?
  fi
  output=$(<"$output_file")
  rm -f "$output_file"
  captured_output=$output
  technical_report "$purpose" "$command_label" "$status" "$output"
  return "$status"
}

technical_transcript_finish() {
  [[ -n "${technical_transcript:-}" && "${technical_transcript_finished:-false}" != true ]] || return 0
  technical_transcript_finished=true
  printf '\nTechnical transcript: %s\n' "$technical_transcript"
}
