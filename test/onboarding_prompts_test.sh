#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ONBOARD_PYTHON="$root/.venv/bin/python"
source "$root/scripts/lib/onboarding/prompts.sh"

presentation_output=$(NO_COLOR=1 major_step '1 of 5' 'Connect' 'Use a stable address' 2>&1)
[[ "$presentation_output" == *'1 of 5 · Connect'* ]]
[[ "$presentation_output" == *'Use a stable address'* ]]
[[ "$presentation_output" != *$'\033['* ]]
NO_COLOR=1 major_step '1 of 5' 'Connect' 'Use a stable address' >/dev/null 2>&1

presentation_output=$(detail_block 'Detected printer' 'Model|Brother MFC-7360N' 'USB ID|04f9:0270' 2>&1)
[[ "$presentation_output" == *'Detected printer'* ]]
[[ "$presentation_output" == *'Model'* && "$presentation_output" == *'Brother MFC-7360N'* ]]

presentation_output=$(confirmation_block 'Printer connection' 'Connection|USB' 'URI|ipp://localhost:60000/ipp/print' 2>&1)
[[ "$presentation_output" == *'Confirmed · Printer connection'* ]]
[[ "$presentation_output" == *'Connection'* && "$presentation_output" == *'USB'* ]]

selected=$(ask 'Queue name' 'printer' <<< 'office-printer')
[[ "$selected" == office-printer ]]

defaulted=$(ask 'Queue name' 'printer' <<< '')
[[ "$defaulted" == printer ]]

# On a real terminal, a typed value is already visible from the terminal's own echo, so ask()
# should not repeat it. A silently accepted default is not visible anywhere else, so it must
# still be echoed back.
ask_stderr=$(mktemp "${TMPDIR:-/tmp}/onboarding-prompts-test.XXXXXX")
interactive_terminal() { return 0; }
ask 'Queue name' 'printer' <<< 'office-printer' 2>"$ask_stderr" >/dev/null
[[ "$(<"$ask_stderr")" != *'Selected:'* ]]
ask 'Queue name' 'printer' <<< '' 2>"$ask_stderr" >/dev/null
[[ "$(<"$ask_stderr")" == *'Selected: printer'* ]]
choice_stderr=$(ask_choice 'Printer connection' 'ipp' ipp ipps socket <<< 'ipps' 2>&1 >/dev/null)
[[ "$choice_stderr" != *'Accepted choice:'* ]]
choice_stderr=$(ask_choice 'Printer connection' 'ipp' ipp ipps socket <<< '' 2>&1 >/dev/null)
[[ "$choice_stderr" == *'Accepted choice: ipp'* ]]
interactive_terminal() { [[ -t 0 && -t 1 ]]; }
rm -f "$ask_stderr"

detected=$(ask_detected 'Trusted IPv4 LAN CIDR' '192.168.178.0/24' 'Do not enter the Raspberry Pi address itself.' <<< '')
[[ "$detected" == 192.168.178.0/24 ]]
valid_ipv4_cidr '192.168.178.0/24'
if valid_ipv4_cidr '192.168.178.4/24'; then
  exit 1
fi
valid_ipv6_cidr 'fd00:1234::/64'
if valid_ipv6_cidr 'fd00::1::/64'; then
  exit 1
fi

choice=$(ask_choice 'Printer connection' 'ipp' ipp ipps socket <<< '')
[[ "$choice" == ipp ]]

same_direct_ipv4_link '192.168.50.1/30' '192.168.50.2'
if same_direct_ipv4_link '192.168.50.1/30' '192.168.50.6'; then
  exit 1
fi
if same_direct_ipv4_link '192.168.50.0/30' '192.168.50.1'; then
  exit 1
fi
if same_direct_ipv4_link '192.168.50.1/30' '192.168.50.3'; then
  exit 1
fi

valid_usb_identity '04a9:1909'
if valid_usb_identity '04a9:190'; then
  exit 1
fi

profile=$(choose_package_profile '' <<< '')
[[ "$profile" == brlaser ]]

valid_printer_uri ipp 'ipp://printer.local/ipp/print'
valid_printer_uri socket 'socket://printer.local:9100'
if valid_printer_uri socket 'ipp://printer.local/ipp/print'; then
  exit 1
fi

[[ "$(printer_uri_default socket direct_ethernet 'socket://192.168.50.2:9100' '192.168.50.2')" == 'socket://192.168.50.2:9100' ]]
[[ "$(printer_uri_default socket direct_ethernet '' '192.168.50.2')" == 'socket://192.168.50.2:9100' ]]
[[ "$(printer_uri_default ipp network '' '')" == 'ipp://printer.local/ipp/print' ]]
valid_ocr_languages 'eng, deu_legacy'
if valid_ocr_languages 'eng;deu'; then
  exit 1
fi

usb_devices=$(usb_device_descriptions $'Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub\nBus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub\nBus 001 Device 004: ID 04f9:0270 Brother Industries, Ltd MFC-7360N')
[[ "$usb_devices" == 'Brother Industries, Ltd MFC-7360N - 04f9:0270' ]]

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

yes_default 'Apply now?' <<< ''
if yes_default 'Apply now?' <<< 'no'; then
  exit 1
fi

if recovery_choice 'Recovery' retry retry stop <<< 'retry'; then
  exit 1
fi

interactive_recovery=$(printf 'manual\n' | script -qefc "bash -c 'source \"$root/scripts/lib/onboarding/prompts.sh\"; choice=\$(recovery_choice \"Discovery recovery\" retry retry manual stop); printf \"RESULT:%s\\n\" \"\$choice\"'" /dev/null)
[[ "$interactive_recovery" == *'RESULT:manual'* ]]

[[ "$(scanner_backend_default network)" == sane-airscan ]]
[[ -z "$(scanner_backend_default usb)" ]]
[[ "$(scanner_backend_guidance usb)" == *'sane-utils provides'* ]]
[[ "$(scanner_backend_guidance usb)" == *'device-compatible SANE backend package'* ]]

# Ticket 010: select_device (manage-devices edit/delete) selects among existing
# managed devices, where "manual" entry is meaningless and previously exited
# with an error if picked. choose_existing_candidate must never offer it.
candidate_count=0
existing_menu=$(choose_existing_candidate 'Select the managed printer.' 'office-printer|office-printer' 'label-printer|label-printer' <<< '2' 2>&1)
[[ "$existing_menu" != *'Enter details manually'* ]]
selected=$(printf '%s' "$existing_menu" | tail -n 1)
[[ "$selected" == 'label-printer|label-printer' ]]

candidate_count=0
invalid_then_valid=$(choose_existing_candidate 'Select the managed printer.' 'office-printer|office-printer' <<< $'9\n1' 2>&1)
[[ "$invalid_then_valid" == *'Enter a listed number.'* ]]
