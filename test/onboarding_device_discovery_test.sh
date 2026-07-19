#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/device-discovery.sh"

candidates=$(ipp_usb_printer_candidates \
  $'network ipp://printer.local/ipp/print\nnetwork dnssd://Office%20Printer._ipp._tcp.local/\nnetwork dnssd://Scanner._uscan._tcp.local/' \
  'network ipp://printer.local/ipp/print')
[[ "$candidates" == 'IPP-over-USB printer (dnssd://Office%20Printer._ipp._tcp.local/)|usb|dnssd://Office%20Printer._ipp._tcp.local/|ipp_usb' ]]

if ipp_usb_printer_candidates 'network ipp://localhost:60000/ipp/print' 'network ipp://localhost:60000/ipp/print' | grep -q .; then
  exit 1
fi
[[ "$(ipp_usb_printer_candidates 'network ipp://localhost:60000/ipp/print' 'network ipp')" == 'IPP-over-USB printer (ipp://localhost:60000/ipp/print)|usb|ipp://localhost:60000/ipp/print|ipp_usb' ]]

legacy=$(cups_printer_candidates $'network ipp\ndirect usb://Generic/Printer?serial=123')
[[ "$legacy" == 'USB printer (usb://Generic/Printer?serial=123)|usb|usb://Generic/Printer?serial=123|legacy_usb' ]]

network=$(cups_printer_candidates $'network ipp\nnetwork ipp://192.0.2.20/ipp/print\nnetwork ipps://printer.local/ipp/print\nnetwork socket://192.0.2.21:9100\nnetwork lpd://192.0.2.22/queue')
[[ "$network" == $'Network printer (ipp://192.0.2.20/ipp/print)|ipp|ipp://192.0.2.20/ipp/print|\nNetwork printer (ipps://printer.local/ipp/print)|ipps|ipps://printer.local/ipp/print|\nNetwork printer (socket://192.0.2.21:9100)|socket|socket://192.0.2.21:9100|\nNetwork printer (lpd://192.0.2.22/queue)|lpd|lpd://192.0.2.22/queue|' ]]

if ipp_usb_check_has_device $'Configuration files: OK\nNo IPP over USB devices found'; then
  exit 1
fi
ipp_usb_check_has_device $'Configuration files: OK\nBus 001 Device 004: compatible IPP-over-USB device'

scanners=$(sane_scanner_candidates $'device `airscan:e0:Office Scanner\' is a WSD scanner\ndevice `genesys:libusb:001:004\' is a USB scanner\ndevice `vendor:net:192.0.2.30\' is a backend-specific scanner')
[[ "$scanners" == $'airscan:e0:Office Scanner (SANE AirScan detected)|ipp|sane-airscan||airscan:e0:Office Scanner\ngenesys:libusb:001:004 (SANE USB detected)|usb|sane-utils|legacy_usb|genesys:libusb:001:004' ]]

ipp_usb_scanners=$(ipp_usb_scanner_candidates \
  $'device `airscan:e0:Existing\' is a scanner\ndevice `airscan:e1:USB MFD\' is a scanner' \
  $'device `airscan:e0:Existing\' is a scanner')
[[ "$ipp_usb_scanners" == 'airscan:e1:USB MFD (SANE through ipp-usb)|usb|sane-airscan|ipp_usb|airscan:e1:USB MFD' ]]

[[ "$(first_sane_scanner_identifier $'device `vendor:net:192.0.2.30\' is a scanner')" == 'vendor:net:192.0.2.30' ]]
direct_scanner=$(direct_scanner_candidate $'device `airscan:e0:192.168.50.9\' is a scanner\ndevice `airscan:e1:192.168.50.2\' is a scanner' '192.168.50.2')
[[ "$direct_scanner" == *'192.168.50.2'* ]]
if direct_scanner_candidate $'device `airscan:e0:192.168.50.9\' is a scanner' '192.168.50.2'; then
  exit 1
fi
sane_hardware_detected 'found USB scanner at libusb:001:004'
if sane_hardware_detected 'sane-find-scanner: command not found'; then
  exit 1
fi

deduplicated=$(printf '%s\n' \
  'Printer one|ipp|ipp://printer.local/ipp/print|' \
  'Printer duplicate|ipp|ipp://printer.local/ipp/print|' \
  'Printer two|socket|socket://192.0.2.20:9100|' | unique_candidates 3)
[[ "$deduplicated" == $'Printer one|ipp|ipp://printer.local/ipp/print|\nPrinter two|socket|socket://192.0.2.20:9100|' ]]

scanner_hints=$(avahi_scanner_hints $'=;eth0;IPv4;Office Scanner;_uscan._tcp;local;scanner.local;192.0.2.40;8080;"rs=eSCL"\n=;eth0;IPv4;Secure Scanner;_uscans._tcp;local;secure.local;192.0.2.41;443;"rs=eSCL"\n=;eth0;IPv4;Legacy Scanner;_scanner._tcp;local;legacy.local;192.0.2.42;6566;')
[[ "$scanner_hints" == $'Office Scanner at scanner.local:8080 (_uscan._tcp)|scanner.local|8080|_uscan._tcp\nSecure Scanner at secure.local:443 (_uscans._tcp)|secure.local|443|_uscans._tcp\nLegacy Scanner at legacy.local:6566 (_scanner._tcp)|legacy.local|6566|_scanner._tcp' ]]

network_scanner=$(sane_scanner_candidates $'device `net:192.0.2.40:vendor:dev0\' is a network scanner')
[[ "$network_scanner" == 'net:192.0.2.40:vendor:dev0 (SANE network detected)|network|sane-utils||net:192.0.2.40:vendor:dev0' ]]

candidate_matches_scope 'USB printer|usb|usb://printer|legacy_usb' usb
candidate_matches_scope 'LAN printer|ipp|ipp://printer/ipp/print|' lan
if candidate_matches_scope 'USB printer|usb|usb://printer|legacy_usb' lan; then
  exit 1
fi
candidate_matches_scope 'USB printer|usb|usb://printer|legacy_usb' all

rg -q 'recommend_legacy_profile' "$root/scripts/onboard"
rg -q 'verify_cups_job' "$root/scripts/onboard"
rg -q 'verify_scanservjs_ready' "$root/scripts/onboard"
rg -q 'test -s' "$root/scripts/onboard"

step_action() {
  local output_var=$1
  printf -v "$output_var" '%s' "$mock_submission"
  return "$mock_submission_status"
}
remote() {
  if [[ "$*" == *'lpstat -W all -l'* ]]; then
    printf '%s\n' "$mock_job_state"
  fi
}
sleep() { :; }

mock_submission_status=1
mock_submission='lp: Bad destination'
rejected=$(verify_cups_job office 2>&1)
[[ "$rejected" == *'CUPS rejected'* ]]

mock_submission_status=0
mock_submission='request id is office-42 (1 file(s))'
mock_job_state='office-42 user 1024 completed at now'
completed=$(verify_cups_job office)
[[ "$completed" == *'office-42'* && "$completed" == *'physical output'* ]]

mock_job_state='office-42 user 1024 aborted at now: printer stopped'
terminal_failure=$(verify_cups_job office)
[[ "$terminal_failure" == *'aborted'* ]]

mock_job_state='office-42 user 1024 processing since now'
pending=$(verify_cups_job office)
[[ "$pending" == *'still pending after 30 seconds'* ]]

step_check() {
  local output_var=$1
  printf -v "$output_var" '%s' "$mock_listener"
  return "$mock_listener_status"
}
mock_listener_status=0
mock_listener='LISTEN 0 511 127.0.0.1:8080'
ready=$(verify_scanservjs_ready 8080)
[[ "$ready" == *'ready on its configured local TCP port 8080'* ]]
mock_listener_status=1
if verify_scanservjs_ready 8080 >/dev/null 2>&1; then
  exit 1
fi

source "$root/scripts/lib/onboarding/prompts.sh"

variables="$root/inventories/production/group_vars/print_servers.yml"
backups="$root/.onboard-backups"
ONBOARD_PYTHON="$root/.venv/bin/python"

# socket:// and lpd:// URIs must never trigger an IPP identity probe.
probe_calls=0
step_check() { probe_calls=$((probe_calls + 1)); return 1; }
remote() { probe_calls=$((probe_calls + 1)); return 1; }

socket_output=$(recommend_legacy_profile 'socket://192.0.2.20:9100' 2>&1)
[[ "$probe_calls" -eq 0 ]]
[[ "$socket_output" == *'No IPP identity probe is available'* ]]
[[ "$socket_output" != *'Recommended profile'* ]]

probe_calls=0
lpd_output=$(recommend_legacy_profile 'lpd://192.0.2.21/queue' 2>&1)
[[ "$probe_calls" -eq 0 ]]
[[ "$lpd_output" == *'No IPP identity probe is available'* ]]
[[ "$lpd_output" != *'Recommended profile'* ]]

# An ipp:// URI with matching IPP identity evidence yields a recommendation
# alongside its "recommendation only, not proof" disclaimer.
step_check() {
  local output_var=$1
  printf -v "$output_var" '%s' 'make-and-model: Brother MFC-7360N'
  return 0
}
matched=$(recommend_legacy_profile 'ipp://printer.local/ipp/print')
[[ "$matched" == *'recommendations only'* && "$matched" == *'do not prove support or select a profile'* ]]
[[ "$matched" == *'Recommended profile brlaser'* ]]

# When the probe fails (no usable evidence), no profile is recommended and the
# manual-selection path via choose_package_profile is still reachable and
# still requires an explicit operator choice.
step_check() {
  local output_var=$1
  printf -v "$output_var" ''
  return 1
}
unmatched=$(recommend_legacy_profile 'ipps://printer.local/ipp/print' 2>&1)
[[ "$unmatched" == *'Choose a package profile manually'* ]]
[[ "$unmatched" != *'Recommended profile'* ]]

manual_choice=$(choose_package_profile '' <<< 'brlaser')
[[ "$manual_choice" == brlaser ]]

# Ticket 015: the additional-printer and additional-scanner discovery offers in
# scripts/onboard now set discovery_kind before calling discover_devices, matching
# manage-devices' discover_for_add. Drive discover_devices end-to-end with both a
# printer and a scanner candidate present, and confirm discovery_kind=printer
# suppresses the scanner candidate menu while discovery_kind=scanner suppresses the
# printer candidate menu.
remote() {
  case "$*" in
    *'timeout 10s lpinfo -v'*) printf 'network ipp://printer.local/ipp/print\n'; return 0 ;;
    *'sudo ipp-usb check'*) printf 'no IPP over USB devices found'; return 1 ;;
    *'scanimage -L'*) printf "device \`airscan:e0:Office Scanner' is a WSD scanner\n"; return 0 ;;
    *) return 0 ;;
  esac
}
remote_tty() { return 0; }
avahi_browse_scan() { return 0; }
choose_candidate() { printf 'manual'; }
recovery_choice() { printf 'manual'; return 0; }
technical_report() { :; }
step_check() {
  local output_variable=$1 output status
  shift 3
  output=$("$@" 2>&1) && status=0 || status=$?
  printf -v "$output_variable" '%s' "$output"
  return "$status"
}
step_action() { step_check "$@"; }
step_stream() { step_check "$@"; }

discovery_kind=printer
printer_scoped_output=$(discover_devices true all)
unset discovery_kind
[[ "$printer_scoped_output" == *'Select a discovered printer or choose manual entry'* ]]
[[ "$printer_scoped_output" != *'Select a discovered scanner or choose manual entry'* ]]

discovery_kind=scanner
scanner_scoped_output=$(discover_devices true all)
unset discovery_kind
[[ "$scanner_scoped_output" == *'Select a discovered scanner or choose manual entry'* ]]
[[ "$scanner_scoped_output" != *'Select a discovered printer or choose manual entry'* ]]

# Without discovery_kind set (the default 'all'), both menus are offered.
unscoped_output=$(discover_devices true all)
[[ "$unscoped_output" == *'Select a discovered printer or choose manual entry'* ]]
[[ "$unscoped_output" == *'Select a discovered scanner or choose manual entry'* ]]

rm -f "${TMPDIR:-/tmp}"/raspberry-print-server-discovery.*.log
