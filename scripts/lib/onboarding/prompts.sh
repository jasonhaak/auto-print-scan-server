#!/usr/bin/env bash

need() { command -v "$1" >/dev/null || { printf 'Missing command: %s\n' "$1" >&2; exit 1; }; }
stage() {
  printf '\n========================================\n[%s] %s\n========================================\n%s\n' "$1" "$2" "$3"
}
recommendation() { printf '\nRecommendation\n  %s\n' "$1"; }
subsection() { printf '\n--- %s ---\n' "$1"; }
ask() {
  local value
  read -r -p "$1 [$2]: " value
  value=${value:-$2}
  printf 'Selected: %s\n' "$value" >&2
  printf '%s' "$value"
}
ask_detected() {
  local prompt=$1 detected=$2 explanation=$3
  printf 'Detected: %s. Press Enter to use this value if it is correct. %s\n' "$detected" "$explanation" >&2
  ask "$prompt" "$detected"
}
yes() {
  local value
  read -r -p "$1 [y/N]: " value
  if [[ "$value" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    printf '%s\n' 'Selected: yes' >&2
    return 0
  fi
  printf '%s\n' 'Selected: no' >&2
  return 1
}
ask_choice() {
  local prompt=$1 default=$2 value option
  shift 2
  while true; do
    read -r -p "$prompt [$default]: " value
    value=${value:-$default}
    for option in "$@"; do
      [[ "$value" == "$option" ]] && { printf 'Accepted choice: %s\n' "$value" >&2; printf '%s' "$value"; return; }
    done
    printf 'Invalid choice: %s. Expected one of: %s. Please try again.\n' "$value" "$*" >&2
  done
}
valid_ipv4_cidr() {
  local address prefix octet
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
  address=${1%/*}; prefix=${1#*/}; (( prefix <= 32 )) || return 1
  IFS=. read -r -a octet <<<"$address"
  for value in "${octet[@]}"; do (( value <= 255 )) || return 1; done
}
valid_ipv6_cidr() {
  local prefix=${1#*/}
  [[ "$1" =~ ^[0-9A-Fa-f:]+/[0-9]{1,3}$ ]] && (( prefix <= 128 ))
}
same_direct_ipv4_link() {
  local pi_cidr=$1 device=$2 pi_address pi_prefix pi_last device_last
  valid_ipv4_cidr "$pi_cidr" && valid_ipv4_cidr "$device/32" || return 1
  pi_address=${pi_cidr%/*}
  pi_prefix=${pi_cidr#*/}
  (( pi_prefix == 30 )) || return 1
  pi_last=${pi_address##*.}
  device_last=${device##*.}
  [[ ${pi_address%.*} == ${device%.*} ]] && (( pi_last / 4 == device_last / 4 && pi_last != device_last ))
}
quote() { local value=$1; value=${value//\\/\\\\}; value=${value//\"/\\\"}; printf '"%s"' "$value"; }
choose_candidate() {
  local title=$1 selection index
  shift
  printf '\n%s\n' "$title" >&2
  for index in "$@"; do
    printf '  %d) %s\n' "$((++candidate_count))" "${index%%|*}" >&2
  done
  printf '  %d) Enter details manually\n' "$((candidate_count + 1))" >&2
  while true; do
    selection=$(ask 'Choose a number' "$((candidate_count + 1))")
    [[ "$selection" =~ ^[0-9]+$ ]] || { printf '%s\n' 'Enter a listed number.' >&2; continue; }
    if (( selection == candidate_count + 1 )); then
      printf '%s' manual
      return
    fi
    if (( selection >= 1 && selection <= candidate_count )); then
      printf '%s' "${@:selection:1}"
      return
    fi
    printf '%s\n' 'Enter a listed number.' >&2
  done
}
choose_usb_identity() {
  local lsusb_output=$1 line identity description choice
  local -a candidates=()
  while IFS='|' read -r identity description; do
    [[ -n "$identity" ]] || continue
    candidates+=("${description:-USB device} (${identity})|$identity")
  done < <(printf '%s\n' "$lsusb_output" | sed -nE 's/.*ID ([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4})[[:space:]]*(.*)/\1|\2/p')
  (( ${#candidates[@]} > 0 )) || return 1
  if (( ${#candidates[@]} == 1 )); then
    identity=${candidates[0]##*|}
    ask_detected 'USB vendor:product identity from lsusb' "$identity" 'This USB device was detected on the Raspberry Pi. Enter a different value only when it is not the intended printer.'
    return
  fi
  candidate_count=0
  choice=$(choose_candidate 'USB devices detected on the Raspberry Pi. Select the intended printer or enter an identity manually.' "${candidates[@]}")
  [[ "$choice" == manual ]] && { printf '%s' manual; return; }
  printf '%s' "${choice##*|}"
}
usb_device_descriptions() {
  printf '%s\n' "$1" | sed -nE 's/.*ID ([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4})[[:space:]]*(.*)/\2 — \1/p' | awk '!/[Rr]oot hub/ && !/[[:space:]]Hub([[:space:]]|$)/'
}
saved_scalar() {
  local key=$1 fallback=$2 value
  [[ -f "$variables" ]] || { printf '%s' "$fallback"; return; }
  value=$(awk -F': ' -v key="$key" '$1 == key {gsub(/^"|"$/, "", $2); print $2; exit}' "$variables")
  printf '%s' "${value:-$fallback}"
}
