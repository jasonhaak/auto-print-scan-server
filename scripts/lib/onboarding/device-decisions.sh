#!/usr/bin/env bash

collect_legacy_printer_profile() {
  local uri=$1 profile_default=${2:-}
  COLLECTED_PRINTER_IDENTITY_EVIDENCE=''
  recommend_legacy_profile "$uri"
  COLLECTED_PRINTER_IDENTITY_EVIDENCE=${legacy_printer_identity_evidence:-}
  COLLECTED_PRINTER_PROFILE=$(choose_package_profile "$profile_default")
}

prepare_legacy_printer_model() {
  local profile=$1 uri=$2 evidence=${3:-}
  prepare_and_choose_cups_model "$profile" "$uri" "$evidence" || return 1
  COLLECTED_PRINTER_PROFILE=$LEGACY_SELECTED_PACKAGE_PROFILE
  COLLECTED_PRINTER_CUPS_MODEL=$LEGACY_SELECTED_CUPS_MODEL
}

collect_scanner_backend() {
  local connection=$1 backend_default=$2 install_default=$3
  scanner_backend_guidance "$connection"
  COLLECTED_SCANNER_BACKEND=$(ask 'SANE backend name' "$backend_default")
  COLLECTED_SCANNER_BACKEND_INSTALL=$(ask_choice 'Install this backend package with APT' "$install_default" true false)
}

scanner_usb_mode_guidance() {
  printf '%s\n' 'Choose ipp_usb only for an IPP-over-USB capable driverless scanner. Choose legacy_usb when the scanner needs a package-provided SANE backend. The final run checks the connected device before enabling ipp-usb.' >&2
}

collect_usb_identity_from_lsusb() {
  local candidate
  if ! candidate=$(choose_usb_identity "$(remote 'lsusb' 2>&1 || true)"); then
    printf '%s\n' 'No USB identity could be detected automatically. Enter the four-digit vendor and product values after ID from lsusb, for example ID 04a9:1909 becomes 04a9:1909.' >&2
    candidate=$(ask 'USB vendor:product identity from lsusb' '')
  elif [[ "$candidate" == manual ]]; then
    candidate=$(ask 'USB vendor:product identity from lsusb' '')
  fi
  while ! valid_usb_identity "$candidate"; do
    printf '%s\n' 'USB identity must use four hexadecimal vendor and product digits, for example 04a9:1909.' >&2
    candidate=$(ask 'USB vendor:product identity from lsusb' "$candidate")
  done
  printf '%s' "$candidate"
}

collect_printer_definition() {
  local topology_default=network
  [[ "${discovered_printer_connection:-}" == usb ]] && topology_default=usb
  printf '\n%s\n' 'Choose how this device reaches the Raspberry Pi. This controls which discovery and connection settings are used.' >&2
  printf '%s\n' 'Connection preference, when the device supports it:' \
    '  1. network: Ethernet through the router or switch. This is the simplest path and can support standard printing and scanning.' \
    '  2. direct_ethernet: Ethernet directly to an unused Raspberry Pi port when the device cannot reach the router.' \
    '  3. usb: a fallback that often supports printing; scanning needs a usable Linux SANE backend.' >&2
  printf '\n' >&2
  recommendation 'Choose network for a device on the home LAN. The wizard detects the capabilities the device actually provides and does not promise scanning for every connection type.'
  local -a topology_options=(network usb)
  [[ -z "$direct_ethernet_interface" ]] && topology_options=(network direct_ethernet usb)
  local topology
  topology=$(ask_choice 'How is this device connected to the Raspberry Pi?' "$topology_default" "${topology_options[@]}")
  if [[ "$topology" == direct_ethernet ]]; then
    discovered_printer_connection=''
    discovered_printer_uri=''
    discovered_printer_usb_mode=''
    collect_direct_ethernet_link || {
      COLLECTED_PRINTER_TOPOLOGY=''
      return 1
    }
  fi
  if [[ "$topology" == usb && "${discovered_printer_connection:-}" != usb ]]; then
    discovered_printer_connection=''
    discovered_printer_uri=''
    discovered_printer_usb_mode=''
  elif [[ "$topology" != usb && "${discovered_printer_connection:-}" == usb ]]; then
    discovered_printer_connection=''
    discovered_printer_uri=''
    discovered_printer_usb_mode=''
  fi
  local connection
  if [[ "$topology" == usb ]]; then
    connection=usb
    printf '%s\n' 'USB was selected for this printer. Its USB identity below identifies the exact device to CUPS.' >&2
  else
    printf '%s\n' 'Choose ipp for most modern network printers. Use ipps for encrypted IPP, socket for JetDirect printers (usually port 9100) or lpd for older LPD printers.' >&2
    if [[ -n "${discovered_printer_connection:-}" && "$topology" == network ]]; then
      printf '\n' >&2
      recommendation "Keep the detected ${discovered_printer_connection} connection if it matches the intended printer."
    fi
    connection=$(ask_choice 'Printer connection' "${discovered_printer_connection:-ipp}" ipp ipps socket lpd)
  fi
  printf '%s\n' 'The device URI tells CUPS where this printer is. For IPP, a common example is ipp://192.168.178.50/ipp/print. Find the exact URI in the printer web administration page or manual, then keep a discovered value unless it is wrong.' >&2
  [[ -n "${discovered_printer_uri:-}" ]] && printf 'Detected printer URI: %s. Press Enter to keep it if it matches the intended printer.\n' "$discovered_printer_uri" >&2
  local uri_default uri
  uri_default=$(printer_uri_default "$connection" "$topology" "${discovered_printer_uri:-}" "$direct_ethernet_device_ipv4")
  while true; do
    uri=$(ask 'Printer device URI' "$uri_default")
    valid_printer_uri "$connection" "$uri" && break
    printf 'The %s connection requires a matching URI scheme. Check the example and try again.\n' "$connection" >&2
  done
  local usb_mode='' usb_identity=''
  if [[ "$connection" == usb ]]; then
    printf '%s\n' 'Choose ipp_usb only for an IPP-over-USB capable driverless printer. Choose legacy_usb for a package-profile printer. The final run checks the connected device before enabling ipp-usb.' >&2
    usb_mode=$(ask_choice 'USB mode' "${discovered_printer_usb_mode:-ipp_usb}" ipp_usb legacy_usb)
    if ! usb_identity=$(choose_usb_identity "$(remote 'lsusb' 2>&1 || true)"); then
      printf '%s\n' 'No USB identity could be detected automatically. Enter the four-digit vendor and product values after ID from lsusb, for example ID 04a9:1909 becomes 04a9:1909.' >&2
      usb_identity=$(ask 'USB vendor:product identity from lsusb' '')
    elif [[ "$usb_identity" == manual ]]; then
      usb_identity=$(ask 'USB vendor:product identity from lsusb' '')
    fi
    while ! valid_usb_identity "$usb_identity"; do
      printf '%s\n' 'USB identity must use four hexadecimal vendor and product digits, for example 04a9:1909.' >&2
      usb_identity=$(ask 'USB vendor:product identity from lsusb' "$usb_identity")
    done
    while [[ "$usb_mode" == legacy_usb && "$uri" != usb://* ]]; do
      printf '%s\n' 'Legacy USB uses the usb:// device URI reported by lpinfo -v.' >&2
      uri=$(ask 'Printer device URI' 'usb://manufacturer/printer')
    done
    while [[ "$usb_mode" == ipp_usb && "$uri" == usb://* ]]; do
      printf '%s\n' 'IPP-over-USB uses its discovered DNS-SD or IPP endpoint, not a legacy usb:// URI.' >&2
      uri=$(ask 'Printer device URI' 'dnssd://printer._ipp._tcp.local/')
    done
  fi
  COLLECTED_PRINTER_TOPOLOGY=$topology
  COLLECTED_PRINTER_CONNECTION=$connection
  COLLECTED_PRINTER_URI=$uri
  COLLECTED_PRINTER_USB_MODE=$usb_mode
  COLLECTED_PRINTER_USB_IDENTITY=$usb_identity
}

collect_scanner_definition() {
  local topology_default=network
  [[ "${discovered_scanner_connection:-}" == usb ]] && topology_default=usb
  local -a topology_options=(network ipp ipps usb)
  [[ -z "$direct_ethernet_interface" ]] && topology_options=(network direct_ethernet ipp ipps usb)
  printf '\n%s\n' 'Choose how this device reaches the Raspberry Pi. network is an exact SANE identifier reached over IP (including a preinstalled backend'"'"'s own net: identifier); ipp/ipps request a driverless eSCL/AirScan endpoint explicitly; usb is a fallback that needs a usable Linux SANE backend for the device.' >&2
  local connection
  connection=$(ask_choice 'Scanner connection' "${discovered_scanner_connection:-$topology_default}" "${topology_options[@]}")
  if [[ "$connection" == direct_ethernet ]]; then
    discovered_scanner_connection=''
    discovered_scanner_backend=''
    discovered_scanner_usb_mode=''
    collect_direct_ethernet_link || {
      COLLECTED_SCANNER_CONNECTION=''
      return 1
    }
    connection=${discovered_scanner_connection:-network}
  fi
  collect_scanner_backend "$connection" "${discovered_scanner_backend:-$(scanner_backend_default "$connection")}" "${discovered_scanner_backend_install:-true}"
  local backend=$COLLECTED_SCANNER_BACKEND backend_install=$COLLECTED_SCANNER_BACKEND_INSTALL
  local usb_mode='' usb_identity=''
  if [[ "$connection" == usb ]]; then
    scanner_usb_mode_guidance
    usb_mode=$(ask_choice 'Scanner USB mode' "${discovered_scanner_usb_mode:-ipp_usb}" ipp_usb legacy_usb)
    usb_identity=$(collect_usb_identity_from_lsusb)
  fi
  COLLECTED_SCANNER_CONNECTION=$connection
  COLLECTED_SCANNER_BACKEND=$backend
  COLLECTED_SCANNER_BACKEND_INSTALL=$backend_install
  COLLECTED_SCANNER_USB_MODE=$usb_mode
  COLLECTED_SCANNER_USB_IDENTITY=$usb_identity
}

select_or_collect_device() {
  local kind=$1 choice search_prompt
  local -n kind_candidates="${kind}_candidates"
  while true; do
    if (( ${#kind_candidates[@]} == 0 )); then
      if [[ "${discovery_tools_ready:-false}" == true ]]; then
        search_prompt="Search again for $kind recommendations?"
      else
        search_prompt="Search for $kind recommendations before defining it?"
      fi
      if yes_default "$search_prompt"; then
        discovery_kind=$kind
        discover_devices true all "${discovery_tools_ready:-false}"
        unset discovery_kind
        discovery_tools_ready=true
        continue
      fi
      choice=manual
      break
    fi
    input_required "${kind^} selection"
    if [[ "$kind" == printer ]]; then
      printer_candidate_details "${kind_candidates[@]}"
    else
      scanner_candidate_details "${kind_candidates[@]}"
    fi
    printf '\n' >&2
    recommendation "Option 1 matches the discovery evidence shown above. Choose it unless it isn't the intended $kind."
    candidate_count=0
    choice=$(choose_candidate "Detected ${kind}s" "${kind_candidates[@]}")
    if [[ "$choice" == manual ]] && yes_default "Search for more $kind recommendations instead of entering details manually?"; then
      discovery_kind=$kind
      discover_devices true all "${discovery_tools_ready:-false}"
      unset discovery_kind
      discovery_tools_ready=true
      continue
    fi
    break
  done
  if [[ "$choice" != manual ]]; then
    remove_candidate "${kind}_candidates" "$choice"
  fi
  if [[ "$kind" == printer ]]; then
    select_or_collect_printer "$choice"
  else
    select_or_collect_scanner "$choice"
  fi
}

select_or_collect_printer() {
  local choice=$1 queue dns_sd_name dns_sd_name_default
  if [[ "$choice" != manual ]]; then
    IFS='|' read -r _ discovered_printer_connection discovered_printer_uri discovered_printer_usb_mode <<<"$choice"
  fi
  input_required 'Printer queue'
  printf '%s\n' 'The queue name is what phones, computers and tablets will see when choosing this printer.' >&2
  while true; do
    queue=$(ask 'CUPS queue name' 'printer')
    [[ "$queue" =~ ^[A-Za-z0-9_.-]+$ ]] && break
    printf '%s\n' 'Use only letters, numbers, dots, underscores and hyphens.' >&2
  done
  dns_sd_name_default=$queue
  while true; do
    dns_sd_name=$(ask 'Client-visible DNS-SD name' "$dns_sd_name_default")
    [[ "$dns_sd_name" =~ ^[A-Za-z0-9_.-]+$ ]] && break
    printf '%s\n' 'Use only letters, numbers, dots, underscores and hyphens.' >&2
  done
  input_required 'Printer connection'
  collect_printer_definition || {
    printf 'Direct Ethernet setup failed for %s. Choose another connection topology or add it again later.\n' "$queue" >&2
    return 1
  }
  local driver=driverless profile='' printer_identity_evidence=''
  if [[ "$COLLECTED_PRINTER_CONNECTION" == usb ]]; then
    if [[ "$COLLECTED_PRINTER_USB_MODE" == legacy_usb ]]; then driver=package_profile; else driver=driverless; fi
    printf 'Using %s driver mode to match %s.\n' "$driver" "$COLLECTED_PRINTER_USB_MODE" >&2
  else
    printf '%s\n' 'Choose driverless first. It uses the printer built-in IPP support and needs no manufacturer driver. Choose package_profile only for an older printer that needs an installed driver package.' >&2
    local driver_default=driverless
    [[ "$COLLECTED_PRINTER_CONNECTION" == socket || "$COLLECTED_PRINTER_CONNECTION" == lpd ]] && driver_default=package_profile
    driver=$(ask_choice 'Printer driver mode' "$driver_default" driverless package_profile)
  fi
  if [[ "$driver" == package_profile ]]; then
    printf '%s\n' 'A package_profile printer needs its driver package installed and its exact CUPS model selected on the Raspberry Pi. That happens in its own step, after every device has been added and before the final review.' >&2
    collect_legacy_printer_profile "$COLLECTED_PRINTER_URI" ''
    printer_identity_evidence=$COLLECTED_PRINTER_IDENTITY_EVIDENCE
    profile=$COLLECTED_PRINTER_PROFILE
  fi
  COLLECTED_PRINTER_QUEUE=$queue
  COLLECTED_PRINTER_DNS_SD_NAME=$dns_sd_name
  COLLECTED_PRINTER_DRIVER=$driver
  COLLECTED_PRINTER_PROFILE=$profile
  COLLECTED_PRINTER_IDENTITY_EVIDENCE=$printer_identity_evidence
  printer_connection_confirmation "$queue" "$COLLECTED_PRINTER_CONNECTION" "$COLLECTED_PRINTER_URI" "$driver" "$COLLECTED_PRINTER_USB_MODE" "$COLLECTED_PRINTER_USB_IDENTITY"
}

select_or_collect_scanner() {
  local choice=$1 device_name display_name
  if [[ "$choice" != manual ]]; then
    IFS='|' read -r _ discovered_scanner_connection discovered_scanner_backend discovered_scanner_usb_mode discovered_scanner_device_name discovered_scanner_backend_install <<<"$choice"
  fi
  input_required 'Scanner device name'
  if [[ "$choice" != manual ]]; then
    printf 'Detected SANE device name: %s. Press Enter to keep it, or enter another identifier if this is not the intended scanner.\n' "$discovered_scanner_device_name" >&2
  else
    printf '%s\n' 'The SANE device name identifies this exact scanner. On the Raspberry Pi, run scanimage -L and copy the text inside the quotes after device, for example airscan:e0:Office_Scanner.' >&2
  fi
  while true; do
    device_name=$(ask 'Exact SANE device name from scanimage -L' "${discovered_scanner_device_name:-}")
    [[ -n "$device_name" ]] && break
    printf '%s\n' 'Scanner device name cannot be empty.' >&2
  done
  printf '%s\n' 'The friendly name is shown in the ScanservJS web interface instead of the raw SANE identifier above.' >&2
  while true; do
    display_name=$(ask 'Friendly scanner name' "$device_name")
    [[ -n "$display_name" ]] && break
    printf '%s\n' 'Friendly scanner name cannot be empty.' >&2
  done
  input_required 'Scanner connection'
  collect_scanner_definition || {
    printf 'Direct Ethernet setup failed for %s. Choose another connection topology or add it again later.\n' "$device_name" >&2
    return 1
  }
  COLLECTED_SCANNER_DEVICE_NAME=$device_name
  COLLECTED_SCANNER_DISPLAY_NAME=$display_name
  if (( ${#scanner_device_names[@]} == 0 )); then
    collect_scanservjs_settings
  fi
  confirmation_block "Scanner: $device_name" \
    "Display name|$display_name" "Connection|$COLLECTED_SCANNER_CONNECTION" "Backend|$COLLECTED_SCANNER_BACKEND" \
    "Backend install|$COLLECTED_SCANNER_BACKEND_INSTALL" "USB mode|${COLLECTED_SCANNER_USB_MODE:-not applicable}" \
    "USB ID|${COLLECTED_SCANNER_USB_IDENTITY:-not applicable}"
}

collect_scanservjs_settings() {
  recommendation 'Choose 90 days as a starting point. Completed scans are visible to the trusted LAN until this period expires.'
  while true; do
    retention=$(ask 'Scan retention days (1-900, recommended 90)' '90')
    [[ "$retention" =~ ^[0-9]+$ ]] && (( retention >= 1 && retention <= 900 )) && break
    printf '%s\n' 'Retention must be 1 to 900 days.' >&2
  done
  recommendation 'OCR makes scanned PDFs searchable. Use eng for English. Add deu for German, separated with commas. More languages can make OCR slower.'
  while true; do
    ocr=$(ask 'OCR language codes, comma-separated' 'eng')
    valid_ocr_languages "$ocr" && break
    printf '%s\n' 'Use comma-separated language codes containing letters, numbers or underscores.' >&2
  done
  recommendation 'The ScanservJS port is the local TCP port its web interface listens on. Change it only if 8080 conflicts with another service.'
  while true; do
    scanservjs_port=$(ask 'ScanservJS port (1-65535, recommended 8080)' "$(saved_scalar scanservjs_port 8080)")
    [[ "$scanservjs_port" =~ ^[0-9]+$ ]] && (( scanservjs_port >= 1 && scanservjs_port <= 65535 )) && break
    printf '%s\n' 'Port must be 1 to 65535.' >&2
  done
  printf '%s\n' 'When enabled, ScanservJS also writes one PDF per scanned page alongside the normal multipage PDF.' >&2
  page_splitting=$(ask_choice 'Enable page splitting (one PDF per scanned page)? (true, false)' 'false' true false)
}

printer_connection_confirmation() {
  confirmation_block "Printer: $1" \
    "Connection|$2" "URI|$3" "Driver|$4" \
    "USB mode|${5:-not applicable}" "USB ID|${6:-not applicable}"
}
