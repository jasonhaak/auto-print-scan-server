#!/usr/bin/env bash

technical_redact() {
  sed -E \
    -e 's/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt])([=:])[[:graph:]]+/\1\2[REDACTED]/g' \
    -e 's/([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*)[[:graph:]]+/\1[REDACTED]/g'
}

cli_color() {
  local code=$1 text=$2
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

cli_status() {
  local status=$1
  if [[ "$status" == 0 ]]; then
    cli_color '32' '[OK]'
  else
    cli_color '31' '[ERROR]'
  fi
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
  local output line_count
  output=$(printf '%s' "$raw_output" | technical_redact)
  {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$purpose"
    printf 'Command: %s\nStatus: %s\n' "$command_label" "$status"
    [[ -n "$output" ]] && printf 'Output:\n%s\n' "$output"
  } >>"$technical_transcript"

  printf '\n%s\n' "$(cli_color '36' '──────────────── Technical details ────────────────')"
  printf '%s %s\n' "$(cli_color '36' 'Check:')" "$purpose"
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
  printf '%s\n' "$(cli_color '36' '────────────────────────────────────────────────────')"
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
