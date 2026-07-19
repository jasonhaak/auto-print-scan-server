#!/usr/bin/env bash

restore_systemd_unit_state() {
  local unit=$1 was_enabled=$2 was_active=$3
  if [[ "$was_active" != active ]]; then
    remote_tty "sudo systemctl stop $(printf '%q' "$unit")" >/dev/null 2>&1 || true
  fi
  case "$was_enabled" in
    enabled|enabled-runtime) remote_tty "sudo systemctl enable $(printf '%q' "$unit")" >/dev/null 2>&1 || true ;;
    masked|masked-runtime) remote_tty "sudo systemctl mask $(printf '%q' "$unit")" >/dev/null 2>&1 || true ;;
    *) remote_tty "sudo systemctl disable $(printf '%q' "$unit")" >/dev/null 2>&1 || true ;;
  esac
  if [[ "$was_active" == active ]]; then
    remote_tty "sudo systemctl start $(printf '%q' "$unit")" >/dev/null 2>&1 || true
  fi
}

restore_ipp_usb_state() {
  [[ "${discovery_ipp_usb_restore_needed:-false}" == true ]] || return 0
  restore_systemd_unit_state ipp-usb.service "${discovery_ipp_usb_was_enabled:-}" "${discovery_ipp_usb_was_active:-}"
  discovery_ipp_usb_restore_needed=false
}

restore_cups_state() {
  [[ "${discovery_cups_restore_needed:-false}" == true ]] || return 0
  restore_systemd_unit_state cups.service "${discovery_cups_was_enabled:-}" "${discovery_cups_was_active:-}"
  restore_systemd_unit_state cups.socket "${discovery_cups_socket_was_enabled:-}" "${discovery_cups_socket_was_active:-}"
  restore_systemd_unit_state cups.path "${discovery_cups_path_was_enabled:-}" "${discovery_cups_path_was_active:-}"
  discovery_cups_restore_needed=false
}

cups_printer_candidates() {
  local output=$1 class uri connection
  while read -r class uri _; do
    [[ -n "${class:-}" && -n "${uri:-}" ]] || continue
    case "$class:$uri" in
      direct:usb://*)
        printf 'USB printer (%s)|usb|%s|legacy_usb\n' "$uri" "$uri"
        continue
        ;;
      network:ipp://*) connection=ipp ;;
      network:ipps://*) connection=ipps ;;
      network:socket://*) connection=socket ;;
      network:lpd://*) connection=lpd ;;
      *) continue ;;
    esac
    printf 'Network printer (%s)|%s|%s|\n' "$uri" "$connection" "$uri"
  done <<<"$output"
}

ipp_usb_check_has_device() {
  local output=$1
  [[ -n "$output" ]] && ! grep -qiE 'no IPP over USB devices found|no devices found' <<<"$output"
}

unique_candidates() {
  local key_field=$1
  awk -F'|' -v key_field="$key_field" 'NF && !seen[$key_field]++'
}

avahi_browse_scan() {
  local status
  remote 'timeout 15s avahi-browse -artp'
  status=$?
  [[ "$status" == 124 ]] && return 0
  return "$status"
}

candidate_matches_scope() {
  local candidate=$1 scope=${2:-all} connection
  IFS='|' read -r _ connection _ <<<"$candidate"
  case "$scope" in
    all) return 0 ;;
    lan) [[ "$connection" != usb ]] ;;
    usb) [[ "$connection" == usb ]] ;;
    *) return 1 ;;
  esac
}

avahi_scanner_hints() {
  local output=$1 event interface protocol name service domain device_host address port txt
  while IFS=';' read -r event interface protocol name service domain device_host address port txt; do
    [[ "$event" == '=' && "$interface" != lo ]] || continue
    case "$service" in
      _uscan._tcp|_uscans._tcp|_scanner._tcp)
        [[ "$address" == 127.* || "$address" == ::1 ]] && continue
        printf '%s at %s:%s (%s)|%s|%s|%s\n' "$name" "$device_host" "$port" "$service" "$device_host" "$port" "$service"
        ;;
    esac
  done <<<"$output"
}

ipp_usb_printer_candidates() {
  local discovered=$1 existing=${2:-} line uri
  while IFS= read -r line; do
    grep -Fqx -- "$line" <<<"$existing" && continue
    uri=${line#* }
    case "$uri" in
      ipp://*|ipps://*) ;;
      dnssd://*._ipp._tcp*|dnssd://*._ipps._tcp*) ;;
      *) continue ;;
    esac
    printf 'IPP-over-USB printer (%s)|usb|%s|ipp_usb\n' "$uri" "$uri"
  done <<<"$discovered"
}

ipp_usb_scanner_candidates() {
  local discovered=$1 existing=${2:-} line scanner_identifier
  while IFS= read -r line; do
    [[ "$line" == device\ \`* ]] || continue
    grep -Fqx -- "$line" <<<"$existing" && continue
    scanner_identifier=${line#device \`}
    scanner_identifier=${scanner_identifier%%\'*}
    [[ -n "$scanner_identifier" ]] || continue
    printf '%s (SANE through ipp-usb)|usb|sane-airscan|ipp_usb|%s\n' "$scanner_identifier" "$scanner_identifier"
  done <<<"$discovered"
}

sane_scanner_candidates() {
  local output=$1 line scanner_identifier
  while IFS= read -r line; do
    [[ "$line" == device\ \`* ]] || continue
    scanner_identifier=${line#device \`}
    scanner_identifier=${scanner_identifier%%\'*}
    [[ -n "$scanner_identifier" ]] || continue
    case "$scanner_identifier" in
      airscan:*)
        printf '%s (SANE AirScan detected)|ipp|sane-airscan||%s\n' "$scanner_identifier" "$scanner_identifier"
        ;;
      escl:*)
        printf '%s (SANE eSCL detected)|ipp|sane-utils||%s\n' "$scanner_identifier" "$scanner_identifier"
        ;;
      net:*)
        printf '%s (SANE network detected)|network|sane-utils||%s\n' "$scanner_identifier" "$scanner_identifier"
        ;;
      *libusb*|usb:*)
        printf '%s (SANE USB detected)|usb|sane-utils|legacy_usb|%s\n' "$scanner_identifier" "$scanner_identifier"
        ;;
    esac
  done <<<"$output"
}

first_sane_scanner_identifier() {
  local output=$1 line scanner_identifier
  while IFS= read -r line; do
    [[ "$line" == device\ \`* ]] || continue
    scanner_identifier=${line#device \`}
    scanner_identifier=${scanner_identifier%%\'*}
    [[ -n "$scanner_identifier" ]] && { printf '%s' "$scanner_identifier"; return; }
  done <<<"$output"
}

sane_hardware_detected() {
  grep -qiE 'found (USB|SCSI) scanner' <<<"$1"
}

tcp_port_is_open() {
  local host=$1 port=$2
  remote "python3 -c 'import socket, sys; connection = socket.create_connection((sys.argv[1], int(sys.argv[2])), 2); connection.close()' $(printf '%q' "$host") $(printf '%q' "$port")" >/dev/null 2>&1
}

discover_direct_ethernet_device() {
  local scanner_output candidate snmp_output command_output carrier carrier_status
  recommendation 'Temporarily configure the private Ethernet link now. It is removed after discovery; the same link is recreated only after final confirmation.'
  yes 'Temporarily configure the direct Ethernet link and search this device?' || return
  if ! step_check command_output 'Verify the direct Ethernet interface' "test -d /sys/class/net/$direct_ethernet_interface" \
    remote "test -d /sys/class/net/$(printf '%q' "$direct_ethernet_interface")"; then
    printf 'Interface %s does not exist on the Raspberry Pi. Continue with another topology or correct the interface.\n' "$direct_ethernet_interface" >&2
    return
  fi
  carrier_status=0
  step_check carrier 'Check the direct Ethernet cable carrier' "cat /sys/class/net/$direct_ethernet_interface/carrier" \
    remote "cat /sys/class/net/$(printf '%q' "$direct_ethernet_interface")/carrier" || carrier_status=$?
  if [[ "$carrier_status" != 0 || "$carrier" != 1 ]]; then
    printf 'Interface %s has no Ethernet carrier. Connect the device cable before discovery.\n' "$direct_ethernet_interface" >&2
    return
  fi
  temporary_direct_connection="raspberry-print-server-onboarding-$$"
  if ! step_action command_output 'Configure the temporary direct Ethernet link' "nmcli connection add/up $temporary_direct_connection" \
    remote_tty "sudo nmcli connection add type ethernet ifname $(printf '%q' "$direct_ethernet_interface") con-name $(printf '%q' "$temporary_direct_connection") ipv4.method manual ipv4.addresses $(printf '%q' "$direct_ethernet_pi_ipv4_cidr") ipv4.never-default yes ipv6.method disabled && sudo nmcli connection up $(printf '%q' "$temporary_direct_connection")"; then
    printf '%s\n' 'The private Ethernet link could not be configured. Check the cable, interface name and Raspberry Pi NetworkManager status. Continue with manual device details.' >&2
    remote_tty "sudo nmcli connection delete $(printf '%q' "$temporary_direct_connection")" >/dev/null 2>&1 || true
    temporary_direct_connection=''
    return
  fi
  if ! step_check command_output 'Reach the directly connected device' "ping -c 1 -W 2 $direct_ethernet_device_ipv4" \
    remote "ping -c 1 -W 2 $(printf '%q' "$direct_ethernet_device_ipv4")"; then
    printf 'The device at %s did not answer on the private link. Check its static address and cable.\n' "$direct_ethernet_device_ipv4" >&2
    remote_tty "sudo nmcli connection delete $(printf '%q' "$temporary_direct_connection")" >/dev/null 2>&1 || true
    temporary_direct_connection=''
    return
  fi
  if step_check command_output 'Probe the direct device for IPP printing' "ipptool ipp://$direct_ethernet_device_ipv4/ipp/print get-printer-attributes.test" \
    remote "ipptool -tv $(printf '%q' "ipp://${direct_ethernet_device_ipv4}/ipp/print") get-printer-attributes.test"; then
    discovered_printer_connection=ipp
    discovered_printer_uri="ipp://${direct_ethernet_device_ipv4}/ipp/print"
    printf 'Detected an IPP printer at %s. Its connection and URI are recommended below.\n' "$direct_ethernet_device_ipv4"
  else
    step_check snmp_output 'Ask CUPS SNMP discovery about the direct device' "CUPS SNMP backend $direct_ethernet_device_ipv4" \
      remote "for backend in /usr/lib/cups/backend/snmp /usr/libexec/cups/backend/snmp; do if test -x \"\$backend\"; then sudo \"\$backend\" $(printf '%q' "$direct_ethernet_device_ipv4"); exit; fi; done; exit 127" || true
    candidate=$(cups_printer_candidates "$snmp_output" | sed -n '1p')
    if [[ -n "$candidate" ]]; then
      IFS='|' read -r _ discovered_printer_connection discovered_printer_uri _ <<<"$candidate"
      printf 'Detected a printer at %s through the CUPS SNMP backend. Its reported URI is recommended below.\n' "$direct_ethernet_device_ipv4"
    else
      if tcp_port_is_open "$direct_ethernet_device_ipv4" 9100; then
        technical_report 'Probe the direct device raw printing port' "TCP connect $direct_ethernet_device_ipv4:9100" 0 'Port is open.'
        discovered_printer_connection=socket
        discovered_printer_uri="socket://${direct_ethernet_device_ipv4}:9100"
        printf 'Detected a printer-compatible raw socket at %s:9100. Its connection and URI are recommended below.\n' "$direct_ethernet_device_ipv4"
      else
        technical_report 'Probe the direct device raw printing port' "TCP connect $direct_ethernet_device_ipv4:9100" 1 'Port is closed or unreachable.'
        if tcp_port_is_open "$direct_ethernet_device_ipv4" 515; then
          technical_report 'Probe the direct device LPD port' "TCP connect $direct_ethernet_device_ipv4:515" 0 'Port is open.'
          printf 'Detected an LPD service at %s:515, but its queue name cannot be inferred safely. Enter the exact lpd:// URI from the device documentation.\n' "$direct_ethernet_device_ipv4" >&2
        else
          technical_report 'Probe the direct device LPD port' "TCP connect $direct_ethernet_device_ipv4:515" 1 'Port is closed or unreachable.'
          printf 'No IPP, CUPS-reported, raw-socket or LPD printer endpoint responded at %s. You can still enter an exact printer URI manually.\n' "$direct_ethernet_device_ipv4" >&2
        fi
      fi
    fi
  fi
  step_check scanner_output 'Probe the direct device for scanning' 'airscan-discover; scanimage -L' \
    remote 'airscan-discover 2>&1; scanimage -L 2>&1' || true
  candidate=$(sane_scanner_candidates "$scanner_output" | awk -F'|' '$2 != "usb" { print; exit }')
  if [[ -n "$candidate" ]]; then
    IFS='|' read -r _ discovered_scanner_connection discovered_scanner_backend discovered_scanner_usb_mode discovered_scanner_device_name <<<"$candidate"
    discovered_scanner=true
    printf 'Detected a scanner: %s. Its SANE identifier will be recommended in the scanner section.\n' "$discovered_scanner_device_name"
  fi
  remote_tty "sudo nmcli connection delete $(printf '%q' "$temporary_direct_connection")" >/dev/null 2>&1 || true
  temporary_direct_connection=''
}

discover_devices() {
  local discovery_approved=${1:-false}
  local discovery_scope=${2:-all}
  local ipp_usb_started=false
  local discovery_log install_output network_output usb_output ipp_usb_output='' lpinfo_before='' lpinfo_output='' scanner_before='' scanner_output scanner_hardware_output scanner_hint_output ipp_query_output='' query_output event interface protocol name service domain device_host address port txt rp scheme uri choice candidate new_ipp_candidates
  local lpinfo_output_status=0
  local -a printer_candidates=() scanner_candidates=()
  [[ "$discovery_scope" != skip ]] || { printf '%s\n' 'Device discovery skipped. Connection details will be entered manually.'; return; }
  discovery_log=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-discovery.XXXXXX.log")
  printf '%s\n' 'Discovery can find printers and scanners that are visible on the trusted LAN or connected by USB.'
  recommendation 'Install the discovery tools on the Raspberry Pi. Discovery temporarily starts CUPS and ipp-usb when needed, then restores their prior service state. It does not create queues, firewall rules or scanner services.'
  if [[ "$discovery_approved" != true ]] && ! yes_default 'Install discovery tools and search for printers and scanners?'; then
    rm -f "$discovery_log"
    return
  fi
  printf '%s\n' 'Installing discovery tools. This can take a few minutes on the first run.'
  discovery_ipp_usb_was_enabled=$(remote 'systemctl is-enabled ipp-usb.service 2>/dev/null' || true)
  discovery_ipp_usb_was_active=$(remote 'systemctl is-active ipp-usb.service 2>/dev/null' || true)
  discovery_cups_was_enabled=$(remote 'systemctl is-enabled cups.service 2>/dev/null' || true)
  discovery_cups_was_active=$(remote 'systemctl is-active cups.service 2>/dev/null' || true)
  discovery_cups_socket_was_enabled=$(remote 'systemctl is-enabled cups.socket 2>/dev/null' || true)
  discovery_cups_socket_was_active=$(remote 'systemctl is-active cups.socket 2>/dev/null' || true)
  discovery_cups_path_was_enabled=$(remote 'systemctl is-enabled cups.path 2>/dev/null' || true)
  discovery_cups_path_was_active=$(remote 'systemctl is-active cups.path 2>/dev/null' || true)
  discovery_ipp_usb_restore_needed=true
  discovery_cups_restore_needed=true
  if ! step_stream install_output 'Install printer and scanner discovery tools' 'apt-get update; apt-get install avahi-utils cups cups-ipp-utils sane-utils sane-airscan ipp-usb' \
    remote_tty 'sudo -v && sudo apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y avahi-utils cups cups-ipp-utils sane-utils sane-airscan ipp-usb'; then
    printf '%s\n' 'Discovery tools could not be installed.' >&2
    restore_ipp_usb_state
    restore_cups_state
    rm -f "$discovery_log"
    choice=$(recovery_choice 'Discovery recovery (retry, manual, stop)' retry retry manual stop) || return 1
    case "$choice" in
      retry) discover_devices true "$discovery_scope"; return $? ;;
      manual) printf '%s\n' 'Continue with manual configuration.'; return 0 ;;
      stop) return 1 ;;
    esac
  fi
  printf '%s\n' 'Discovery tools are ready. Searching local network announcements and connected USB devices for up to 15 seconds.'

  if [[ "$discovery_scope" == lan ]]; then
    usb_output='Skipped by LAN-only discovery scope.'
    technical_report 'USB device discovery' 'lsusb' 0 "$usb_output"
  else
    step_check usb_output 'USB device discovery' 'lsusb' remote 'lsusb' || true
  fi
  step_action command_output 'Start CUPS for endpoint discovery' 'systemctl start cups.service' \
    remote_tty 'sudo systemctl start cups.service' || true
  step_action command_output 'Stop IPP-over-USB for direct endpoint discovery' 'systemctl stop ipp-usb.service' \
    remote_tty 'sudo systemctl stop ipp-usb.service' || true
  step_check lpinfo_before 'CUPS endpoint discovery without ipp-usb' 'lpinfo -v' remote 'timeout 10s lpinfo -v' || true
  scanner_before=$(remote 'scanimage -L 2>&1') || true
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && candidate_matches_scope "$candidate" "$discovery_scope" && printer_candidates+=("$candidate")
  done < <(cups_printer_candidates "$lpinfo_before")
  if [[ "$discovery_scope" == lan ]]; then
    ipp_usb_output='Skipped by LAN-only discovery scope.'
    technical_report 'IPP-over-USB compatibility check' 'ipp-usb check' 0 "$ipp_usb_output"
  else
    step_check ipp_usb_output 'IPP-over-USB compatibility check' 'ipp-usb check' remote 'sudo ipp-usb check' || true
  fi
  if [[ "$discovery_scope" != lan ]] && ipp_usb_check_has_device "$ipp_usb_output"; then
    if step_action command_output 'Start IPP-over-USB for USB endpoint discovery' 'systemctl start ipp-usb.service' \
      remote_tty 'sudo systemctl start ipp-usb.service'; then
      ipp_usb_started=true
      for _ in {1..5}; do
        if lpinfo_output=$(remote 'timeout 2s lpinfo -v' 2>&1); then lpinfo_output_status=0; else lpinfo_output_status=$?; fi
        new_ipp_candidates=$(ipp_usb_printer_candidates "$lpinfo_output" "$lpinfo_before")
        [[ -n "$new_ipp_candidates" ]] && break
        sleep 1
      done
      while IFS= read -r candidate; do
        [[ -n "$candidate" ]] && printer_candidates+=("$candidate")
      done <<<"$new_ipp_candidates"
    fi
  fi
  if [[ "$discovery_scope" != usb ]]; then
    step_stream network_output 'LAN service discovery' 'avahi-browse -artp' avahi_browse_scan || true
  else
    network_output='Skipped by USB-only discovery scope.'
    technical_report 'LAN service discovery' 'avahi-browse -artp' 0 "$network_output"
  fi
  step_check scanner_output 'SANE scanner discovery' 'scanimage -L' remote 'airscan-discover 2>&1; scanimage -L 2>&1' || true
  if [[ "$discovery_scope" == lan ]]; then
    scanner_hardware_output='Skipped by LAN-only discovery scope.'
    technical_report 'Low-level scanner hardware discovery' 'sane-find-scanner -q' 0 "$scanner_hardware_output"
  else
    step_check scanner_hardware_output 'Low-level scanner hardware discovery' 'sane-find-scanner -q' remote 'sudo sane-find-scanner -q 2>&1' || true
  fi
  restore_ipp_usb_state
  restore_cups_state
  scanner_hint_output=$(avahi_scanner_hints "$network_output")
  while IFS=';' read -r event interface protocol name service domain device_host address port txt; do
    [[ "$event" == '=' ]] || continue
    case "$service" in
      _ipp._tcp|_ipps._tcp)
        [[ "$discovery_scope" == usb ]] && continue
        [[ "$address" == 127.* || "$address" == ::1 || "$interface" == lo ]] && continue
        scheme=${service#_}
        scheme=${scheme%%._tcp}
        rp=$(printf '%s' "$txt" | sed -nE 's/.*rp=([^" ]+).*/\1/p' | sed -n '1p')
        rp=${rp:-ipp/print}
        rp=${rp#/}
        uri="$scheme://$device_host:$port/$rp"
        if step_check query_output "Verify announced printer $name" "ipptool $uri get-printer-attributes.test" \
          remote "ipptool -tv $(printf '%q' "$uri") get-printer-attributes.test"; then
          printer_candidates+=("$name at $device_host:$port ($scheme)|$scheme|$uri|")
        else
          ipp_query_output+="$name at $address:$port: $query_output"$'\n'
        fi
        ;;
      _uscan._tcp|_uscans._tcp|_scanner._tcp) ;;
    esac
  done <<<"$network_output"
  if [[ "$ipp_usb_started" == true ]]; then
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] && candidate_matches_scope "$candidate" "$discovery_scope" && scanner_candidates+=("$candidate")
    done < <(ipp_usb_scanner_candidates "$scanner_output" "$scanner_before")
  fi
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && candidate_matches_scope "$candidate" "$discovery_scope" && scanner_candidates+=("$candidate")
  done < <(sane_scanner_candidates "$scanner_output")
  mapfile -t printer_candidates < <(printf '%s\n' "${printer_candidates[@]}" | unique_candidates 3)
  mapfile -t scanner_candidates < <(printf '%s\n' "${scanner_candidates[@]}" | unique_candidates 5)
  {
    printf '%s\n%s\n%s\n%s\n' 'Network discovery:' "$network_output" 'USB discovery:' "$usb_output"
    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' 'IPP-over-USB check:' "$ipp_usb_output" \
      'CUPS device discovery before ipp-usb:' "$lpinfo_before" 'CUPS device discovery with ipp-usb:' "$lpinfo_output" \
      'IPP queries:' "$ipp_query_output" 'SANE discovery before ipp-usb:' "$scanner_before"
    printf '%s\n%s\n' 'SANE discovery with ipp-usb:' "$scanner_output"
    printf '%s\n%s\n' 'Low-level scanner hardware discovery:' "$scanner_hardware_output"
    printf '%s\n%s\n' 'Advertised scanner hints:' "$scanner_hint_output"
  } >"$discovery_log"

  [[ -n "$lpinfo_output" ]] && technical_report 'CUPS endpoint discovery with ipp-usb' 'lpinfo -v' "$lpinfo_output_status" "$lpinfo_output"

  if [[ -n "$scanner_hint_output" ]]; then
    printf '\nAdvertised network scanners\n'
    while IFS='|' read -r hint_label _; do
      [[ -n "$hint_label" ]] && printf '  - %s\n' "$hint_label"
    done <<<"$scanner_hint_output"
    printf '%s\n' 'Announcements are discovery hints. A scanner is selectable only when SANE reports an exact identifier.'
  fi

  printf 'Discovery completed: %d printer candidate(s), %d scanner candidate(s).\n' "${#printer_candidates[@]}" "${#scanner_candidates[@]}"
  (( ${#printer_candidates[@]} > 0 )) || printf '%s\n' 'No printer was found. Find its IPP address in its web administration page or manual, for example ipp://192.168.178.50/ipp/print.'
  if (( ${#scanner_candidates[@]} == 0 )); then
    if [[ -n "$scanner_hint_output" ]]; then
      printf '%s\n' 'A scanner was advertised on the LAN but SANE did not report an exact usable identifier. Review the technical output, confirm the scanner protocol is enabled and retry before configuring it manually.'
    elif [[ -n "$(first_sane_scanner_identifier "$scanner_output")" ]]; then
      discovered_scanner_device_name=$(first_sane_scanner_identifier "$scanner_output")
      printf 'SANE reported scanner %s, but its transport is backend-specific and could not be inferred safely. The exact identifier will be suggested during manual scanner setup.\n' "$discovered_scanner_device_name"
    elif sane_hardware_detected "$scanner_hardware_output"; then
      printf '%s\n' 'Scanner-like USB hardware was found, but SANE did not report a usable device identifier. Install the device-compatible SANE backend, then run scanimage -L again.'
    else
      printf '%s\n' 'No scanner was found. Connect it, then run scanimage -L on the Raspberry Pi and copy the reported device line.'
    fi
  fi

  if (( ${#printer_candidates[@]} > 0 )) && [[ "${discovery_kind:-all}" != scanner ]]; then
    input_required 'Select a discovered printer or choose manual entry'
    candidate_count=0
    choice=$(choose_candidate 'Discovered printers. Select the device to configure or enter details manually.' "${printer_candidates[@]}")
    if [[ "$choice" != manual ]]; then
      IFS='|' read -r selected_printer_label discovered_printer_connection discovered_printer_uri discovered_printer_usb_mode <<<"$choice"
      printf 'Selected detected printer: %s. Its connection and URI will be suggested below.\n' "$selected_printer_label"
    fi
  fi
  if (( ${#scanner_candidates[@]} > 0 )) && [[ "${discovery_kind:-all}" != printer ]]; then
    input_required 'Select a discovered scanner or choose manual entry'
    candidate_count=0
    choice=$(choose_candidate 'Discovered scanners. Select one to configure or enter details manually.' "${scanner_candidates[@]}")
    if [[ "$choice" != manual ]]; then
      IFS='|' read -r selected_scanner_label discovered_scanner_connection discovered_scanner_backend discovered_scanner_usb_mode discovered_scanner_device_name <<<"$choice"
      discovered_scanner=true
      printf 'Selected detected scanner: %s. Its detected settings will be suggested below.\n' "$selected_scanner_label"
    fi
  fi
  if [[ -z "${discovered_printer_connection:-}" && "${discovered_scanner:-false}" != true ]]; then
    printf 'No usable device was selected. Continue with manual configuration. Discovery log: %s. Full transcript: %s\n' "$discovery_log" "${technical_transcript:-not available}" >&2
    choice=$(recovery_choice 'Discovery recovery (retry, manual, stop)' retry retry manual stop) || return 1
    case "$choice" in
      retry) rm -f "$discovery_log"; discover_devices true "$discovery_scope"; return $? ;;
      manual) return 0 ;;
      stop) return 1 ;;
    esac
  else
    rm -f "$discovery_log"
  fi
}
