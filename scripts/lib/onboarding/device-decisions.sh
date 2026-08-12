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
  printf '%s\n' 'Choose ipp_usb only for an IPP-over-USB capable driverless scanner. Choose legacy_usb when the scanner needs a package-provided SANE backend.' >&2
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
    [[ -n "${discovered_printer_connection:-}" && "$topology" == network ]] && recommendation "Keep the detected ${discovered_printer_connection} connection if it matches the intended printer."
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
  collect_scanner_backend "$connection" "${discovered_scanner_backend:-$(scanner_backend_default "$connection")}" true
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

printer_connection_confirmation() {
  confirmation_block 'Printer connection' \
    "Queue|$1" "Connection|$2" "URI|$3" "Driver|$4" \
    "USB mode|${5:-not applicable}" "USB ID|${6:-not applicable}"
}
