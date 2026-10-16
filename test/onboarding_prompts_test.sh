#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -x "$root/.venv/bin/python" ]]; then
  ONBOARD_PYTHON="$root/.venv/bin/python"
else
  ONBOARD_PYTHON=$(command -v python3)
fi
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
[[ "$(<"$ask_stderr")" != *'Selected:'* ]]
choice_stderr=$(ask_choice 'Printer connection' 'ipp' ipp ipps socket <<< 'ipps' 2>&1 >/dev/null)
[[ "$choice_stderr" != *'Accepted choice:'* ]]
choice_stderr=$(ask_choice 'Printer connection' 'ipp' ipp ipps socket <<< '' 2>&1 >/dev/null)
[[ "$choice_stderr" != *'Accepted choice:'* ]]
interactive_terminal() { [[ -t 0 && -t 1 ]]; }
rm -f "$ask_stderr"

detected=$(ask_detected 'Trusted IPv4 LAN CIDR' '192.168.178.0/24' 'Do not enter the server address itself.' <<< '')
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
[[ "$(package_profile_model_prefix brlaser)" == 'drv:///brlaser.drv/' ]]
candidate_count=0
selected_cups_model=$(choose_cups_model brlaser 'usb://Brother/MFC-7360N?serial=example' \
  $'drv:///brlaser.drv/br7360.ppd Brother MFC-7360N\ndrv:///brlaser.drv/br7040.ppd Brother DCP-7040' \
  'drv:///brlaser.drv/' <<< '1')
[[ "$selected_cups_model" == 'drv:///brlaser.drv/br7360.ppd' ]]

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

# Finding 9: choose_usb_identity must filter root-hub/hub entries the same way
# usb_device_descriptions already does, so a single real device behind two hub entries is
# still detected automatically instead of forcing a three-way menu the administrator has to
# read past.
hub_filtered_identity=$(choose_usb_identity $'Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub\nBus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub\nBus 001 Device 004: ID 04f9:0270 Brother Industries, Ltd MFC-7360N' <<< '')
[[ "$hub_filtered_identity" == 04f9:0270 ]]

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

workspace=$(mktemp -d "${TMPDIR:-/tmp}/onboarding-prompts-test.XXXXXX")
trap 'rm -rf "$workspace"' EXIT

printf 'ssh_allow_password_authentication: true\n' >"$workspace/vars-password.yml"
password_command=$(manual_recovery_command "$root" "$workspace/vars-password.yml" "$root/inventories/production/hosts.yml" playbooks/site.yml -e print_server_commissioning=true 2>&1)
[[ "$password_command" == *'./.venv/bin/ansible-playbook'* ]]
[[ "$password_command" == *'-i inventories/production/hosts.yml'* ]]
[[ "$password_command" == *'playbooks/site.yml'* ]]
[[ "$password_command" == *'-e print_server_commissioning=true'* ]]
[[ "$password_command" == *'--ask-pass'* ]]
[[ "$password_command" == *'--ask-become-pass'* ]]

printf 'ssh_allow_password_authentication: false\n' >"$workspace/vars-key.yml"
key_command=$(manual_recovery_command "$root" "$workspace/vars-key.yml" "$root/inventories/production/hosts.yml" playbooks/site.yml -e print_server_commissioning=true 2>&1)
[[ "$key_command" != *'--ask-pass'* ]]
[[ "$key_command" == *'--ask-become-pass'* ]]

# Finding 7: ask/yes/yes_default/ask_choice already print a trailing blank line, so
# major_step/detail_block/confirmation_block/subsection must not also print a leading one --
# otherwise every prompt-into-block transition shows two blank lines instead of one.
[[ "$(NO_COLOR=1 major_step '1 of 5' 'Connect' 'purpose' 2>&1 | head -n1)" != '' ]]
[[ "$(NO_COLOR=1 detail_block 'Title' 'K|V' 2>&1 | head -n1)" != '' ]]
[[ "$(NO_COLOR=1 confirmation_block 'Title' 'K|V' 2>&1 | head -n1)" != '' ]]
[[ "$(NO_COLOR=1 subsection 'Title' 2>&1 | head -n1)" != '' ]]
[[ "$(NO_COLOR=1 recommendation 'Choose the default.' 2>&1 | head -n1)" != '' ]]

# The design spec's own worked example shows a blank line on both sides of a Recommendation
# block, not just before it: recommendation() must end with a trailing blank line so its
# guidance text doesn't run straight into whatever prompt or content follows.
[[ "$(NO_COLOR=1 recommendation 'Choose the default.' 2>&1 | tail -n1)" == '' ]]

# CLI audit F16: a recommendation() right before choose_candidate always names "Option 1" as
# the best match, so pressing Enter must accept candidate 1, not "Enter details manually" -- a
# wizard that trains the user to press Enter for twenty prompts straight must not make the one
# highest-stakes prompt in the flow do the opposite of what its own recommendation just said.
candidate_count=0
default_choice=$(choose_candidate 'Detected printers' 'Candidate one|a' 'Candidate two|b' <<< '' 2>/dev/null)
[[ "$default_choice" == 'Candidate one|a' ]]

output=$(CATALOG_SUITE=trixie CATALOG_ARCHITECTURE=armhf CATALOG_REPOSITORY=R \
  choose_package_profile '' <<< 'brlaser' 2>&1)
grep -q 'brlaser' <<<"$output" || { echo "curated profile missing" >&2; exit 1; }
if (ONBOARD_PYTHON=false choose_package_profile '' <<< '' 2>&1); then
  echo "expected failure when the resolver cannot run" >&2; exit 1
fi
# no CATALOG_* set must still work (empty argument list, not a blank argument)
choose_package_profile '' <<< 'brlaser' >/dev/null
models=$'foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Other.ppd Other\nfoomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW.ppd Brother HL-2270DW'
choice=$(choose_cups_model generic_pcl 'ipp://printer/ipp/print' "$models" \
  'foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/' 'MFG:Brother;MDL:HL-2270DW;' <<< '1')
[[ "$choice" == 'foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW.ppd' ]] || {
  echo "expected the identity-matched model first, got $choice" >&2; exit 1; }
output=$(choose_cups_model generic_pcl 'ipp://printer/ipp/print' "$models" \
  'foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/' 'MFG:Acme;MDL:Nothing;' <<< '1' 2>&1)
[[ "$output" != *'[recommended]'* ]] || {
  echo "unexpected recommendation for an unmatched identity" >&2; exit 1; }
