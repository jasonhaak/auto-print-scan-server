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
