#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ONBOARD_PYTHON="$root/.venv/bin/python"
variables=''
source "$root/scripts/lib/onboarding/prompts.sh"
source "$root/scripts/lib/onboarding/device-discovery.sh"
source "$root/scripts/lib/onboarding/device-decisions.sh"

remote() { printf ''; }
remote_tty() { return 0; }
recommendation() { :; }
input_required() { :; }

# network/ipp printer, no direct_ethernet claimed yet, no discovered defaults.
ask_choice() {
  case "$1" in
    'How is this device connected to the Raspberry Pi?') printf 'network' ;;
    'Printer connection') printf 'ipp' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
ask() { printf '%s' "$2"; }
direct_ethernet_interface=''
direct_ethernet_device_ipv4=''
discovered_printer_connection=''
discovered_printer_uri=''
discovered_printer_usb_mode=''
printer_candidates=()
scanner_candidates=()
collect_printer_definition
[[ "$COLLECTED_PRINTER_TOPOLOGY" == network ]] || { printf 'expected topology network, got %s\n' "$COLLECTED_PRINTER_TOPOLOGY" >&2; exit 1; }
[[ "$COLLECTED_PRINTER_CONNECTION" == ipp ]] || { printf 'expected connection ipp, got %s\n' "$COLLECTED_PRINTER_CONNECTION" >&2; exit 1; }
[[ "$COLLECTED_PRINTER_URI" == 'ipp://printer.local/ipp/print' ]] || { printf 'unexpected URI: %s\n' "$COLLECTED_PRINTER_URI" >&2; exit 1; }
[[ -z "$COLLECTED_PRINTER_USB_MODE" ]]
[[ -z "$COLLECTED_PRINTER_USB_IDENTITY" ]]
unset -f ask_choice ask

# usb printer: usb mode + identity collected, and legacy_usb forces a usb:// URI.
ask_choice() {
  case "$1" in
    'How is this device connected to the Raspberry Pi?') printf 'usb' ;;
    'USB mode') printf 'legacy_usb' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
choose_usb_identity() { printf '04a9:1909'; return 0; }
ask() {
  case "$1" in
    'Printer device URI') printf 'usb://manufacturer/printer' ;;
    *) printf '%s' "$2" ;;
  esac
}
direct_ethernet_interface=''
discovered_printer_connection=''
discovered_printer_uri=''
discovered_printer_usb_mode=''
collect_printer_definition
[[ "$COLLECTED_PRINTER_TOPOLOGY" == usb ]]
[[ "$COLLECTED_PRINTER_CONNECTION" == usb ]]
[[ "$COLLECTED_PRINTER_USB_MODE" == legacy_usb ]]
[[ "$COLLECTED_PRINTER_USB_IDENTITY" == '04a9:1909' ]]
[[ "$COLLECTED_PRINTER_URI" == 'usb://manufacturer/printer' ]]
unset -f ask_choice ask choose_usb_identity

# collect_scanner_definition: network/ipp scanner, no USB fields collected.
ask_choice() {
  case "$1" in
    'Scanner connection') printf 'network' ;;
    'Install this backend package with APT') printf 'true' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
ask() {
  case "$1" in
    'SANE backend name') printf '%s' "$2" ;;
    *) printf '%s' "$2" ;;
  esac
}
direct_ethernet_interface=''
discovered_scanner_connection=''
discovered_scanner_backend=''
discovered_scanner_usb_mode=''
collect_scanner_definition
[[ "$COLLECTED_SCANNER_CONNECTION" == network ]]
[[ "$COLLECTED_SCANNER_BACKEND" == sane-airscan ]]
[[ -z "$COLLECTED_SCANNER_USB_MODE" ]]
unset -f ask_choice ask

# collect_scanner_definition: usb scanner collects USB mode + identity.
ask_choice() {
  case "$1" in
    'Scanner connection') printf 'usb' ;;
    'Install this backend package with APT') printf 'true' ;;
    'Scanner USB mode') printf 'legacy_usb' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
choose_usb_identity() { printf '04a9:1909'; return 0; }
ask() { printf '%s' "$2"; }
direct_ethernet_interface=''
discovered_scanner_connection=''
discovered_scanner_backend=''
discovered_scanner_usb_mode=''
collect_scanner_definition
[[ "$COLLECTED_SCANNER_CONNECTION" == usb ]]
[[ "$COLLECTED_SCANNER_USB_MODE" == legacy_usb ]]
[[ "$COLLECTED_SCANNER_USB_IDENTITY" == '04a9:1909' ]]
unset -f ask_choice ask choose_usb_identity

# select_or_collect_device(printer): a leftover candidate is offered and, once chosen, removed
# from printer_candidates so it is not offered again on a later loop iteration.
printer_candidates=('Network printer (ipp://192.0.2.20/ipp/print)|ipp|ipp://192.0.2.20/ipp/print|')
scanner_candidates=()
scanner_device_names=()
discovery_tools_ready=false
discovered_printer_connection=''
discovered_printer_uri=''
discovered_printer_usb_mode=''
direct_ethernet_interface=''
choose_candidate() { printf '%s' "$2"; }
printer_candidate_details() { :; }
ask_choice() {
  case "$1" in
    'How is this device connected to the Raspberry Pi?') printf 'network' ;;
    'Printer connection') printf 'ipp' ;;
    'Printer driver mode') printf 'driverless' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
ask() {
  case "$1" in
    'CUPS queue name') printf 'office' ;;
    'Client-visible DNS-SD name') printf 'office' ;;
    *) printf '%s' "$2" ;;
  esac
}
printer_connection_confirmation() { :; }
select_or_collect_device printer
[[ "${#printer_candidates[@]}" -eq 0 ]] || { printf 'selected candidate must be removed from printer_candidates: %s\n' "${printer_candidates[*]}" >&2; exit 1; }
[[ "$COLLECTED_PRINTER_QUEUE" == office ]]
[[ "$COLLECTED_PRINTER_URI" == 'ipp://192.0.2.20/ipp/print' ]]
unset -f choose_candidate printer_candidate_details ask_choice ask printer_connection_confirmation

# collect_scanner_definition must offer to keep (not force-reinstall) a discovered scanner's
# preinstalled backend by passing discovered_scanner_backend_install through as the install
# default, matching the "Detected preinstalled SANE backend" guidance shown alongside it.
ask_choice() {
  case "$1" in
    'Scanner connection') printf 'network' ;;
    'Install this backend package with APT') printf '%s' "$2" ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
ask() { printf '%s' "$2"; }
direct_ethernet_interface=''
discovered_scanner_connection=network
discovered_scanner_backend=brother
discovered_scanner_backend_install=false
discovered_scanner_usb_mode=''
collect_scanner_definition
[[ "$COLLECTED_SCANNER_BACKEND_INSTALL" == false ]] || { printf 'expected the discovered backend_install=false to be kept as the default, got %s\n' "$COLLECTED_SCANNER_BACKEND_INSTALL" >&2; exit 1; }
unset -f ask_choice ask

# select_or_collect_scanner: a friendly display name is collected and defaults to the exact
# SANE device name when the operator just presses Enter.
scanner_candidates=()
printer_candidates=()
scanner_device_names=()
discovered_scanner_connection=''
discovered_scanner_backend=''
discovered_scanner_usb_mode=''
direct_ethernet_interface=''
ask_choice() {
  case "$1" in
    'Scanner connection') printf 'network' ;;
    'Install this backend package with APT') printf 'true' ;;
    'Enable page splitting (one PDF per scanned page)?') printf 'false' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
ask() {
  case "$1" in
    'Scanner device name') printf 'airscan:e0:Office Scanner' ;;
    'Friendly scanner name') printf '%s' "$2" ;;
    *) printf '%s' "$2" ;;
  esac
}
confirmation_block() { :; }
recommendation() { :; }
select_or_collect_scanner manual
[[ "$COLLECTED_SCANNER_DEVICE_NAME" == 'airscan:e0:Office Scanner' ]]
[[ "$COLLECTED_SCANNER_DISPLAY_NAME" == 'airscan:e0:Office Scanner' ]] || { printf 'expected display name to default to the device name, got %s\n' "$COLLECTED_SCANNER_DISPLAY_NAME" >&2; exit 1; }
unset -f ask_choice ask confirmation_block recommendation

# An explicit, distinct display name is kept as entered.
ask_choice() {
  case "$1" in
    'Scanner connection') printf 'network' ;;
    'Install this backend package with APT') printf 'true' ;;
    'Enable page splitting (one PDF per scanned page)?') printf 'false' ;;
    *) printf 'unexpected ask_choice: %s\n' "$1" >&2; exit 1 ;;
  esac
}
ask() {
  case "$1" in
    'Scanner device name') printf 'airscan:e0:Office Scanner' ;;
    'Friendly scanner name') printf 'Office Scanner' ;;
    *) printf '%s' "$2" ;;
  esac
}
confirmation_block() { :; }
recommendation() { :; }
select_or_collect_scanner manual
[[ "$COLLECTED_SCANNER_DISPLAY_NAME" == 'Office Scanner' ]]
unset -f ask_choice ask confirmation_block recommendation

printf 'onboarding_device_decisions_test.sh: all checks passed\n'
