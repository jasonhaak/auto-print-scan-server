#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ONBOARD_PYTHON="$root/.venv/bin/python"
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

printf 'onboarding_device_decisions_test.sh: all checks passed\n'
