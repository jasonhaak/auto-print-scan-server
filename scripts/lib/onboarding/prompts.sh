#!/usr/bin/env bash

need() { command -v "$1" >/dev/null || { printf 'Missing command: %s\n' "$1" >&2; exit 1; }; }
cli_heading() {
  local text=$1
  if declare -F cli_color >/dev/null; then
    cli_color '1;36' "$text"
  else
    printf '%s' "$text"
  fi
}
stage() {
  printf '\n%s\n%s\n%s\n\n%s\n' "$(cli_heading '════════════════════════════════════════════════════')" "$(cli_heading "[$1] $2")" "$(cli_heading '════════════════════════════════════════════════════')" "$3"
}
recommendation() { printf '\n%s\n  %s\n' "$(cli_heading 'Recommendation')" "$1"; }
subsection() { printf '\n%s\n' "$(cli_heading "──── $1 ────")"; }
input_required() { printf '\n%s\n' "$(cli_heading "Input required: $1")"; }
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
yes_default() {
  local value
  read -r -p "$1 [Y/n]: " value
  if [[ -z "$value" || "$value" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    printf '%s\n' 'Selected: yes' >&2
    return 0
  fi
  printf '%s\n' 'Selected: no' >&2
  return 1
}

interactive_terminal() { [[ -t 0 && -t 1 ]]; }

recovery_choice() {
  local prompt=$1
  shift
  if ! interactive_terminal; then
    printf '%s\n' 'Recovery is unavailable without an interactive terminal.' >&2
    return 1
  fi
  ask_choice "$prompt" "$1" "$@"
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
  local strict=${2:-true} checker=${ONBOARD_PYTHON:-python3}
  command -v "$checker" >/dev/null 2>&1 || [[ -x "$checker" ]] || return 1
  "$checker" -c 'import ipaddress, sys; network = ipaddress.ip_network(sys.argv[1], strict=sys.argv[2] == "true"); raise SystemExit(network.version != 4)' "$1" "$strict" >/dev/null 2>&1
}
valid_ipv6_cidr() {
  local checker=${ONBOARD_PYTHON:-python3}
  command -v "$checker" >/dev/null 2>&1 || [[ -x "$checker" ]] || return 1
  "$checker" -c 'import ipaddress, sys; network = ipaddress.ip_network(sys.argv[1], strict=True); raise SystemExit(network.version != 6)' "$1" >/dev/null 2>&1
}
valid_printer_uri() {
  local connection=$1 uri=$2 checker=${ONBOARD_PYTHON:-python3}
  command -v "$checker" >/dev/null 2>&1 || [[ -x "$checker" ]] || return 1
  "$checker" "$root/scripts/lib/device_inventory.py" validate-uri "$connection" "$uri" >/dev/null 2>&1
}
printer_uri_default() {
  local connection=$1 topology=$2 discovered_uri=${3:-} direct_device_ipv4=${4:-}
  [[ -n "$discovered_uri" ]] && { printf '%s' "$discovered_uri"; return; }
  if [[ "$topology" == direct_ethernet && -n "$direct_device_ipv4" ]]; then
    case "$connection" in
      ipp) printf 'ipp://%s/ipp/print' "$direct_device_ipv4" ;;
      ipps) printf 'ipps://%s/ipp/print' "$direct_device_ipv4" ;;
      socket) printf 'socket://%s:9100' "$direct_device_ipv4" ;;
      lpd) printf 'lpd://%s/queue' "$direct_device_ipv4" ;;
      usb) printf '%s' 'dnssd://printer._ipp._tcp.local/' ;;
    esac
    return
  fi
  case "$connection" in
    ipp) printf '%s' 'ipp://printer.local/ipp/print' ;;
    ipps) printf '%s' 'ipps://printer.local/ipp/print' ;;
    socket) printf '%s' 'socket://printer.local:9100' ;;
    lpd) printf '%s' 'lpd://printer.local/queue' ;;
    usb) printf '%s' 'dnssd://printer._ipp._tcp.local/' ;;
  esac
}
valid_ocr_languages() {
  [[ "$1" =~ ^[A-Za-z0-9_]+([[:space:]]*,[[:space:]]*[A-Za-z0-9_]+)*$ ]]
}
same_direct_ipv4_link() {
  local checker=${ONBOARD_PYTHON:-python3}
  command -v "$checker" >/dev/null 2>&1 || [[ -x "$checker" ]] || return 1
  "$checker" -c 'import ipaddress, sys; pi = ipaddress.ip_interface(sys.argv[1]); device = ipaddress.ip_address(sys.argv[2]); network = pi.network; valid = pi.version == 4 and network.prefixlen == 30 and device.version == 4 and device in network and pi.ip not in (network.network_address, network.broadcast_address) and device not in (pi.ip, network.network_address, network.broadcast_address); raise SystemExit(not valid)' "$1" "$2" >/dev/null 2>&1
}
valid_usb_identity() {
  local identity=$1 checker=${ONBOARD_PYTHON:-python3}
  command -v "$checker" >/dev/null 2>&1 || [[ -x "$checker" ]] || return 1
  "$checker" "$root/scripts/lib/device_inventory.py" validate-usb-identity "$identity" >/dev/null 2>&1
}
choose_package_profile() {
  local default=$1 profile
  local -a profiles=()
  while IFS= read -r profile; do
    [[ -n "$profile" ]] && profiles+=("$profile")
  done < <(sed -nE 's/^  ([A-Za-z0-9_.-]+):$/\1/p' "$root/vars/package_profiles.yml")
  (( ${#profiles[@]} > 0 )) || { printf '%s\n' 'No package profiles are registered.' >&2; return 1; }
  [[ -n "$default" ]] || default=${profiles[0]}
  printf 'Available package profiles: %s\n' "${profiles[*]}" >&2
  ask_choice 'Explicit package profile' "$default" "${profiles[@]}"
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
choose_existing_candidate() {
  local title=$1 selection index
  shift
  printf '\n%s\n' "$title" >&2
  for index in "$@"; do
    printf '  %d) %s\n' "$((++candidate_count))" "${index%%|*}" >&2
  done
  while true; do
    selection=$(ask 'Choose a number' 1)
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= candidate_count )); then
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
  printf '%s\n' "$1" | sed -nE 's/.*ID ([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4})[[:space:]]*(.*)/\2 - \1/p' | awk '!/[Rr]oot hub/ && !/[[:space:]]Hub([[:space:]]|$)/'
}
saved_scalar() {
  local key=$1 fallback=$2 value
  [[ -f "$variables" ]] || { printf '%s' "$fallback"; return; }
  value=$(awk -F': ' -v key="$key" '$1 == key {gsub(/^"|"$/, "", $2); print $2; exit}' "$variables")
  printf '%s' "${value:-$fallback}"
}
