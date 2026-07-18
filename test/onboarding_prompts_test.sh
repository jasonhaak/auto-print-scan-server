#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/prompts.sh"

selected=$(ask 'Queue name' 'printer' <<< 'office-printer')
[[ "$selected" == office-printer ]]

defaulted=$(ask 'Queue name' 'printer' <<< '')
[[ "$defaulted" == printer ]]

detected=$(ask_detected 'Trusted IPv4 LAN CIDR' '192.168.178.0/24' 'Do not enter the Raspberry Pi address itself.' <<< '')
[[ "$detected" == 192.168.178.0/24 ]]

choice=$(ask_choice 'Printer connection' 'ipp' ipp ipps socket <<< '')
[[ "$choice" == ipp ]]

same_direct_ipv4_link '192.168.50.1/30' '192.168.50.2'
if same_direct_ipv4_link '192.168.50.1/30' '192.168.50.6'; then
  exit 1
fi

usb_devices=$(usb_device_descriptions $'Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub\nBus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub\nBus 001 Device 004: ID 04f9:0270 Brother Industries, Ltd MFC-7360N')
[[ "$usb_devices" == 'Brother Industries, Ltd MFC-7360N — 04f9:0270' ]]

single_usb_identity=$(choose_usb_identity 'Bus 001 Device 002: ID 04a9:1909 Canon, Inc. printer' <<< '')
[[ "$single_usb_identity" == 04a9:1909 ]]

selected_usb_identity=$(choose_usb_identity $'Bus 001 Device 002: ID 04a9:1909 Canon, Inc. printer\nBus 001 Device 003: ID 03f0:1234 HP, Inc. printer' <<< '2')
[[ "$selected_usb_identity" == 03f0:1234 ]]

manual_usb_identity=$(choose_usb_identity $'Bus 001 Device 002: ID 04a9:1909 Canon, Inc. printer\nBus 001 Device 003: ID 03f0:1234 HP, Inc. printer' <<< '3')
[[ "$manual_usb_identity" == manual ]]

yes 'Use discovery?' <<< 'yes'
if yes 'Use discovery?' <<< 'no'; then
  exit 1
fi
