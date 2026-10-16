#!/usr/bin/env bash

need() { command -v "$1" >/dev/null || { printf 'Missing command: %s\n' "$1" >&2; exit 1; }; }
cli_color() {
  local code=$1 text=$2
  if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}
cli_heading() {
  cli_color '1;36' "$1"
}
cli_error() { printf '%s %s\n' "$(cli_color '31' 'Error:')" "$1" >&2; }
major_step() {
  local number=$1 title=$2 purpose=$3 recap=${4:-}
  printf '%s\n%s\n%s\n%s\n' "$(cli_heading '══════════════════════════════════════════════')" "$(cli_heading "$number · $title")" "$(cli_heading '══════════════════════════════════════════════')" "$purpose" >&2
  [[ -n "$recap" ]] && printf 'Context: %s\n\n' "$recap" >&2
  return 0
}
detail_block() {
  local title=$1 item key value width=12
  shift
  printf '%s\n' "$(cli_heading "──────────────── $title ────────────────")" >&2
  for item in "$@"; do
    key=${item%%|*}
    (( ${#key} > width )) && width=${#key}
  done
  for item in "$@"; do
    key=${item%%|*}; value=${item#*|}
    printf "  %-${width}s %s\n" "$key" "$value" >&2
  done
}
confirmation_block() {
  local title=$1 item key label value width=12
  shift
  printf '%s\n' "$(cli_heading "Confirmed · $title")" >&2
  for item in "$@"; do
    label="${item%%|*}:"
    (( ${#label} > width )) && width=${#label}
  done
  for item in "$@"; do
    key=${item%%|*}; value=${item#*|}
    printf "  %-${width}s %s\n" "$key:" "$value" >&2
  done
}
manual_recovery_command() {
  local root=$1 variables=$2 inventory=$3 playbook=$4
  shift 4
  local relative_inventory=${inventory#"$root"/} command extra
  command="cd $(printf '%q' "$root") && ./.venv/bin/ansible-playbook -i $(printf '%q' "$relative_inventory") $(printf '%q' "$playbook")"
  for extra in "$@"; do
    command+=" $(printf '%q' "$extra")"
  done
  if grep -q '^ssh_allow_password_authentication: true' "$variables" 2>/dev/null; then
    command+=' --ask-pass --ask-become-pass'
  else
    command+=' --ask-become-pass'
  fi
  detail_block 'Manual recovery command' "Command|$command"
}
setup_status() { printf '%s %s\n' "$(cli_color '32' '✓')" "$1" >&2; }
setting_group() { group_header "$1"; }
group_header() { printf '%s\n' "$(cli_heading "──────────────── $1 ────────────────")" >&2; }
stage() {
  local recap=${4:-}
  major_step "$1" "$2" "$3" "$recap"
  return 0
}
recommendation() { printf '%s\n  %s\n\n' "$(cli_color '1;33' 'Recommendation')" "$1" >&2; }
subsection() { printf '%s\n' "$(cli_heading "──── $1 ────")" >&2; }
input_required() { group_header "$1"; }
ask() {
  local raw value
  read -r -p "$1 [$2]: " raw
  value=${raw:-$2}
  # On an interactive terminal, a typed value is already visible from the terminal's own echo;
  # only report it back when a default was silently accepted, or when there is no terminal echo
  # to rely on (piped input, e.g. in tests or scripted runs).
  if ! interactive_terminal; then
    printf 'Selected: %s\n' "$value" >&2
  fi
  printf '\n' >&2
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
    ! interactive_terminal && printf '%s\n' 'Selected: yes' >&2
    printf '\n' >&2
    return 0
  fi
  ! interactive_terminal && printf '%s\n' 'Selected: no' >&2
  printf '\n' >&2
  return 1
}
yes_default() {
  local value
  read -r -p "$1 [Y/n]: " value
  if [[ -z "$value" || "$value" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    ! interactive_terminal && printf '%s\n' 'Selected: yes' >&2
    printf '\n' >&2
    return 0
  fi
  ! interactive_terminal && printf '%s\n' 'Selected: no' >&2
  printf '\n' >&2
  return 1
}

# Recovery choices return their value on stdout, which callers capture. stderr remains attached
# to the administrator terminal for prompts and diagnostics, so use it to identify an interactive
# session without mistaking command substitution for non-interactive execution.
interactive_terminal() { [[ -t 0 && -t 2 ]]; }

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
  local prompt=$1 default=$2 raw value option options_list
  shift 2
  options_list=$(printf '%s, ' "$@")
  printf 'Options: %s\n' "${options_list%, }" >&2
  while true; do
    read -r -p "$prompt [$default]: " raw
    value=${raw:-$default}
    for option in "$@"; do
      if [[ "$value" == "$option" ]]; then
        # Same rationale as ask(): skip the echo only when the terminal already showed the
        # typed value and it was accepted as-is.
        if ! interactive_terminal; then
          printf 'Accepted choice: %s\n' "$value" >&2
        fi
        printf '\n' >&2
        printf '%s' "$value"
        return
      fi
    done
    cli_error "Invalid choice: $value. Expected one of: $*. Please try again."
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
  "$checker" -c 'import ipaddress, sys; server_ip = ipaddress.ip_interface(sys.argv[1]); device = ipaddress.ip_address(sys.argv[2]); network = server_ip.network; valid = server_ip.version == 4 and network.prefixlen == 30 and device.version == 4 and device in network and server_ip.ip not in (network.network_address, network.broadcast_address) and device not in (server_ip.ip, network.network_address, network.broadcast_address); raise SystemExit(not valid)' "$1" "$2" >/dev/null 2>&1
}
valid_usb_identity() {
  local identity=$1 checker=${ONBOARD_PYTHON:-python3}
  command -v "$checker" >/dev/null 2>&1 || [[ -x "$checker" ]] || return 1
  "$checker" "$root/scripts/lib/device_inventory.py" validate-usb-identity "$identity" >/dev/null 2>&1
}
catalog_identity_arguments() {
  local -a arguments=()
  [[ -n "${CATALOG_SUITE:-}" ]] && arguments+=(--catalog-suite "$CATALOG_SUITE")
  [[ -n "${CATALOG_ARCHITECTURE:-}" ]] && arguments+=(--catalog-architecture "$CATALOG_ARCHITECTURE")
  [[ -n "${CATALOG_REPOSITORY:-}" ]] && arguments+=(--catalog-repository "$CATALOG_REPOSITORY")
  [[ -n "${CATALOG_ENABLE_GENERATED:-}" ]] && arguments+=(--enable-generated-catalog)
  (( ${#arguments[@]} > 0 )) && printf '%s\n' "${arguments[@]}"
}
choose_package_profile() {
  local default=$1 profile listing
  local -a profiles=() identity=()
  mapfile -t identity < <(catalog_identity_arguments)
  if ! listing=$("$ONBOARD_PYTHON" "$root/scripts/lib/device_inventory.py" "${identity[@]}" profiles); then
    printf '%s\n' 'The package profile registry could not be read.' >&2
    return 1
  fi
  while IFS= read -r profile; do
    [[ -n "$profile" ]] && profiles+=("$profile")
  done <<<"$listing"
  (( ${#profiles[@]} > 0 )) || { printf '%s\n' 'No package profiles are registered.' >&2; return 1; }
  [[ -n "$default" ]] || default=${profiles[0]}
  printf 'Available package profiles: %s\n' "${profiles[*]}" >&2
  ask_choice 'Explicit package profile' "$default" "${profiles[@]}"
}
package_profile_model_prefix() {
  local -a identity=()
  mapfile -t identity < <(catalog_identity_arguments)
  "$ONBOARD_PYTHON" "$root/scripts/lib/device_inventory.py" "${identity[@]}" profile-model-prefix "$1"
}
identity_match_tokens() {
  local base=$1 evidence=$2 chunk value
  for chunk in $(tr -cs '[:alnum:]' ' ' <<<"$base"); do
    chunk=${chunk,,}
    (( ${#chunk} >= 4 )) && printf '%s\n' "$chunk"
  done
  base=$(tr -cd '[:alnum:]' <<<"${base,,}")
  (( ${#base} >= 4 )) && printf '%s\n' "$base"
  while IFS= read -r value; do
    value=${value#*:}
    for chunk in $(tr -cs '[:alnum:]' ' ' <<<"$value"); do
      chunk=${chunk,,}
      (( ${#chunk} >= 4 )) && printf '%s\n' "$chunk"
    done
    value=$(tr -cd '[:alnum:]' <<<"${value,,}")
    (( ${#value} >= 4 )) && printf '%s\n' "$value"
  done < <(grep -o -E 'MFG:[^;]*|MDL:[^;]*' <<<"$evidence" || true)
}
choose_cups_model() {
  local profile=$1 uri=$2 models=$3 prefix=$4 evidence=${5:-} candidate model description selection recommended='' identity normalized_description score best_score=0 index choice_default show_all=0 show_all_option manual_option position
  local -a candidates=() scores=() tokens=() displayed=()
  identity=${uri%%\?*}
  identity=${identity##*/}
  mapfile -t tokens < <(identity_match_tokens "$identity" "$evidence" | sort -u)
  while IFS= read -r candidate; do
    model=${candidate%%[[:space:]]*}
    description=${candidate#"$model"}
    [[ "$model" == "$prefix"* ]] || continue
    candidates+=("$model${description}|$model")
    normalized_description=$(tr -cd '[:alnum:]' <<<"${description,,}")
    score=0
    for token in ${tokens[@]+"${tokens[@]}"}; do
      [[ "$normalized_description" == *"$token"* ]] && ((score++))
    done
    # A generic PCL model is never inferred from a PCL capability: it stays
    # selectable, but is never narrowed to or recommended.
    [[ "${model,,}" == *generic-pcl_* ]] && score=0
    scores+=("$score")
    if (( score > best_score )); then
      best_score=$score
      recommended=$model
    fi
  done <<<"$models"
  (( ${#candidates[@]} > 0 )) || {
    printf 'CUPS did not advertise a model beginning with %s for profile %s. Choose another profile or inspect lpinfo -m on the server.\n' "$prefix" "$profile" >&2
    return 1
  }
  (( best_score > 0 )) || recommended=''
  while true; do
    displayed=()
    if (( show_all == 0 )) && (( best_score > 0 )); then
      for index in "${!candidates[@]}"; do
        (( scores[index] > 0 )) && displayed+=("$index")
      done
    else
      for index in "${!candidates[@]}"; do displayed+=("$index"); done
    fi
    input_required 'Exact CUPS model'
    printf '%s\n' 'Choose the exact model advertised by CUPS. This is saved for this queue and verified again during commissioning.' >&2
    if (( show_all == 0 )) && (( best_score > 0 )) && (( ${#displayed[@]} < ${#candidates[@]} )); then
      printf '%s\n' 'Only models matching the detected printer identity are listed.' >&2
    fi
    if [[ -n "$recommended" ]]; then
      printf '\n' >&2
      recommendation "Recommended from detected printer identity: $recommended. Confirm it explicitly below."
    else
      printf '\n' >&2
    fi
    printf '%-4s %-46s %s\n' 'No.' 'Model' 'Description' >&2
    position=0
    for index in "${displayed[@]}"; do
      position=$((position + 1))
      model=${candidates[$index]##*|}
      description=${candidates[$index]%%|*}
      description=${description#"$model"}
      printf '%-4s %-46s %s%s\n' "$position" "$model" "${description# }" \
        "$([[ "$model" == "$recommended" ]] && printf '  [recommended]')" >&2
    done
    show_all_option=0
    if (( show_all == 0 )) && (( best_score > 0 )) && (( ${#displayed[@]} < ${#candidates[@]} )); then
      show_all_option=$((position + 1))
      position=$((position + 1))
      printf '%-4s %s\n' "$show_all_option" 'Show all models under this prefix' >&2
    fi
    manual_option=$((position + 1))
    printf '%-4s %s\n' "$manual_option" 'Enter a listed model manually' >&2
    choice_default=$manual_option
    if [[ -n "$recommended" ]]; then
      for position in "${!displayed[@]}"; do
        if [[ "${candidates[${displayed[$position]}]##*|}" == "$recommended" ]]; then
          choice_default=$((position + 1))
          break
        fi
      done
    fi
    while true; do
      selection=$(ask 'Choose a number' "$choice_default")
      [[ "$selection" =~ ^[0-9]+$ ]] || { printf '%s\n' 'Enter a listed number.' >&2; continue; }
      (( selection >= 1 && selection <= manual_option )) && break
      printf '%s\n' 'Enter a listed number.' >&2
    done
    if (( show_all_option > 0 )) && (( selection == show_all_option )); then
      show_all=1
      continue
    fi
    if (( selection == manual_option )); then
      selection=manual
    else
      selection=${candidates[${displayed[$((selection - 1))]}]}
    fi
    break
  done
  if [[ "$selection" == manual ]]; then
    while true; do
      model=$(ask 'Exact CUPS model from lpinfo -m' "${recommended:-${candidates[0]##*|}}")
      for candidate in "${candidates[@]}"; do [[ "${candidate##*|}" == "$model" ]] && { printf '%s' "$model"; return; }; done
      printf '%s\n' 'Enter one of the models advertised above.' >&2
    done
  fi
  printf '%s' "${selection##*|}"
}
scanner_backend_default() {
  [[ "$1" == usb ]] || printf '%s' sane-airscan
}
scanner_backend_guidance() {
  if [[ "$1" == usb ]]; then
    printf '%s\n' 'sane-utils provides scanimage and other tools, but may not recognise a legacy USB scanner. Enter the device-compatible SANE backend package.'
  else
    printf '%s\n' 'Use sane-airscan for most network scanners. It supports modern eSCL and WSD scanning. Enter another documented backend package only when the device requires it.'
  fi
}
quote() { local value=$1; value=${value//\\/\\\\}; value=${value//\"/\\\"}; printf '"%s"' "$value"; }
choose_candidate() {
  local title=$1 selection index
  shift
  printf '%s\n' "$title" >&2
  for index in "$@"; do
    printf '  %d) %s\n' "$((++candidate_count))" "${index%%|*}" >&2
  done
  printf '  %d) Enter details manually\n' "$((candidate_count + 1))" >&2
  while true; do
    selection=$(ask 'Choose a number' 1)
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
  printf '%s\n' "$title" >&2
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
  done < <(printf '%s\n' "$lsusb_output" | sed -nE 's/.*ID ([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4})[[:space:]]*(.*)/\1|\2/p' | awk '!/[Rr]oot hub/ && !/[[:space:]]Hub([[:space:]]|$)/')
  (( ${#candidates[@]} > 0 )) || return 1
  if (( ${#candidates[@]} == 1 )); then
    identity=${candidates[0]##*|}
    ask_detected 'USB vendor:product identity from lsusb' "$identity" 'This USB device was detected on the server. Enter a different value only when it is not the intended printer.'
    return
  fi
  candidate_count=0
  choice=$(choose_candidate 'USB devices detected on the server. Select the intended printer or enter an identity manually.' "${candidates[@]}")
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
