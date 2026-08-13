#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/device-discovery.sh"

candidates=(alpha beta gamma beta)
remove_candidate candidates beta
[[ "${candidates[*]}" == 'alpha gamma beta' ]] || { printf 'remove_candidate did not remove exactly the first match: %s\n' "${candidates[*]}" >&2; exit 1; }

candidates=(solo)
remove_candidate candidates missing
[[ "${candidates[*]}" == 'solo' ]] || { printf 'remove_candidate must leave the array unchanged when there is no match\n' >&2; exit 1; }

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

brother_scanner=$(sane_scanner_candidates $'device `brother:net1;dev0\' is a flatbed scanner')
[[ "$brother_scanner" == 'brother:net1;dev0 (preinstalled Brother backend)|network|brother||brother:net1;dev0|false' ]]
brother_usb_scanner=$(sane_scanner_candidates $'device `brother:bus2;dev1\' is a flatbed scanner')
[[ "$brother_usb_scanner" == 'brother:bus2;dev1 (preinstalled Brother backend)|usb|brother|legacy_usb|brother:bus2;dev1|false' ]]

unsupported_guidance=$(unsupported_scanner_guidance 'brother:other;dev1')
[[ "$unsupported_guidance" == *'brother:other;dev1'* ]]
[[ "$unsupported_guidance" == *'Manual experimental setup'* ]]

ipp_usb_scanners=$(ipp_usb_scanner_candidates \
  $'device `airscan:e0:Existing\' is a scanner\ndevice `airscan:e1:USB MFD\' is a scanner' \
  $'device `airscan:e0:Existing\' is a scanner')
[[ "$ipp_usb_scanners" == 'airscan:e1:USB MFD (SANE through ipp-usb)|usb|sane-airscan|ipp_usb|airscan:e1:USB MFD' ]]

[[ "$(first_sane_scanner_identifier $'device `vendor:net:192.0.2.30\' is a scanner')" == 'vendor:net:192.0.2.30' ]]
direct_scanner=$(direct_scanner_candidate $'device `airscan:e0:192.168.50.9\' is a scanner\ndevice `airscan:e1:192.168.50.2\' is a scanner' '192.168.50.2')
[[ "$direct_scanner" == *'192.168.50.2'* ]]
direct_scanner=$(direct_scanner_candidate $'device `airscan:w0:Office Scanner\' is a WSD scanner ip=192.168.50.2' '192.168.50.2')
[[ "$direct_scanner" == 'airscan:w0:Office Scanner (SANE AirScan detected)|ipp|sane-airscan||airscan:w0:Office Scanner' ]]
if direct_scanner_candidate $'device `airscan:w0:192.168.50.20\' is a WSD scanner' '192.168.50.2'; then
  exit 1
fi
if direct_scanner_candidate $'device `airscan:e0:192.168.50.9\' is a scanner' '192.168.50.2'; then
  exit 1
fi

# Ticket 014: a scanner identified only by hostname is accepted when that
# hostname resolves exclusively (via the Raspberry Pi, not locally) to the
# configured direct device address.
[[ "$(direct_scanner_candidate_host 'airscan:e0:printer.local')" == printer.local ]]
[[ "$(direct_scanner_candidate_host 'escl:printer.local')" == printer.local ]]
[[ "$(direct_scanner_candidate_host 'net:printer.local:vendor:dev0')" == printer.local ]]
# A literal IPv4 host is not treated as a hostname (it is already covered by
# the literal-containment path and must not trigger a remote resolution call).
[[ -z "$(direct_scanner_candidate_host 'airscan:e0:192.168.50.9')" ]]

remote() {
  case "$*" in
    *"getent ahostsv4 printer.local"*) printf '192.168.50.2\n'; return 0 ;;
    *"getent ahostsv4 ambiguous.local"*) printf '192.168.50.2\n192.168.50.3\n'; return 0 ;;
    *"getent ahostsv4 missing.local"*) return 2 ;;
    *) return 1 ;;
  esac
}
direct_scanner_hostname_resolves_exclusively printer.local 192.168.50.2
if direct_scanner_hostname_resolves_exclusively ambiguous.local 192.168.50.2; then
  exit 1
fi
if direct_scanner_hostname_resolves_exclusively missing.local 192.168.50.2; then
  exit 1
fi

hostname_scanner=$(direct_scanner_candidate $'device `airscan:e0:printer.local\' is a scanner' '192.168.50.2')
[[ "$hostname_scanner" == *'airscan:e0:printer.local'* ]]
if direct_scanner_candidate $'device `airscan:e0:ambiguous.local\' is a scanner' '192.168.50.2'; then
  exit 1
fi
if direct_scanner_candidate $'device `airscan:e0:missing.local\' is a scanner' '192.168.50.2'; then
  exit 1
fi
unset -f remote

sane_hardware_detected 'found USB scanner at libusb:001:004'
sane_hardware_detected 'found possible USB scanner at libusb:001:004'
if sane_hardware_detected 'sane-find-scanner: command not found'; then
  exit 1
fi

[[ "$(sane_discovery_outcome '')" == 'SANE discovery returned no usable device identifier.' ]]
[[ "$(sane_discovery_outcome $'device `airscan:e0:Office Scanner\' is a scanner')" == 'SANE discovery returned an exact device identifier.' ]]
grep -Fq 'Run SANE scanner discovery command' "$root/scripts/lib/onboarding/device-discovery.sh"
! grep -Fq "step_check scanner_output 'SANE scanner discovery'" "$root/scripts/lib/onboarding/device-discovery.sh"

no_printer_guidance=$(no_printer_discovery_guidance)
[[ "$no_printer_guidance" == *'trusted LAN or USB'* ]]
[[ "$no_printer_guidance" == *'direct_ethernet topology flow'* ]]

deduplicated=$(printf '%s\n' \
  'Printer one|ipp|ipp://printer.local/ipp/print|' \
  'Printer duplicate|ipp|ipp://printer.local/ipp/print|' \
  'Printer two|socket|socket://192.0.2.20:9100|' | unique_candidates 3)
[[ "$deduplicated" == $'Printer one|ipp|ipp://printer.local/ipp/print|\nPrinter two|socket|socket://192.0.2.20:9100|' ]]

ranked=$(printf '%s\n' \
  'Brother scanner|network|brother||brother:net1;dev0|false' \
  'AirScan scanner|ipp|sane-airscan||airscan:e0:Office Scanner' \
  'USB scanner|usb|sane-utils|legacy_usb|genesys:libusb:001:004' | rank_airscan_first)
[[ "$ranked" == $'AirScan scanner|ipp|sane-airscan||airscan:e0:Office Scanner\nBrother scanner|network|brother||brother:net1;dev0|false\nUSB scanner|usb|sane-utils|legacy_usb|genesys:libusb:001:004' ]]

no_airscan=$(printf '%s\n' \
  'Brother scanner|network|brother||brother:net1;dev0|false' \
  'USB scanner|usb|sane-utils|legacy_usb|genesys:libusb:001:004' | rank_airscan_first)
[[ "$no_airscan" == $'Brother scanner|network|brother||brother:net1;dev0|false\nUSB scanner|usb|sane-utils|legacy_usb|genesys:libusb:001:004' ]]

ipp_usb_ranked=$(printf '%s\n' \
  'Brother scanner|network|brother||brother:net1;dev0|false' \
  'IPP-over-USB scanner|usb|sane-airscan|ipp_usb|Office Scanner' | rank_airscan_first)
[[ "$ipp_usb_ranked" == $'IPP-over-USB scanner|usb|sane-airscan|ipp_usb|Office Scanner\nBrother scanner|network|brother||brother:net1;dev0|false' ]]

grep -q 'rank_airscan_first' "$root/scripts/lib/onboarding/device-discovery.sh"
grep -Fq 'unique_candidates 5 | rank_airscan_first' "$root/scripts/lib/onboarding/device-discovery.sh"

grep -q "ask 'Client-visible DNS-SD name'" "$root/scripts/manage-devices"
grep -q -- '--dns-sd-name' "$root/scripts/manage-devices"

grep -q "ask 'Client-visible DNS-SD name'" "$root/scripts/lib/onboarding/device-decisions.sh"
grep -q 'printer_dns_sd_names' "$root/scripts/onboard"
grep -q 'dns_sd_name:' "$root/scripts/onboard"

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

grep -q 'recommend_legacy_profile' "$root/scripts/lib/onboarding/device-decisions.sh"
grep -q 'verify_cups_job' "$root/scripts/onboard"
grep -q 'verify_scanservjs_ready' "$root/scripts/onboard"
grep -q 'create_scanner_test_pdf' "$root/scripts/onboard"
grep -q 'test -s' "$root/scripts/lib/onboarding/device-discovery.sh"

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

# systemctl start cups.service returns as soon as the unit starts, not once CUPS is actually
# ready to answer lpinfo -- unlike the CUPS role's own provisioning path, which polls lpstat -r
# before touching CUPS. Without the same wait here, lpinfo -v can hit a CUPS that isn't
# listening yet, hang, and get killed by its 10s timeout, silently producing zero printer
# candidates on a real Pi even though a printer is connected. wait_for_cups_ready's retry loop
# runs as a remote shell snippet, so exercise it for real (via remote() { eval "$1"; }, matching
# the create_scanner_test_pdf tests above) rather than mocking step_check away entirely.
step_check() {
  local output_var=$1 purpose=$2 command_label=$3
  shift 3
  local output status
  output=$("$@" 2>&1) && status=0 || status=$?
  printf -v "$output_var" '%s' "$output"
  return "$status"
}
remote() { eval "$1"; }
sleep() { :; }

# The retry loop pipes lpstat through grep -q, and the whole snippet runs inside a command
# substitution, so a plain shell variable can't survive across iterations -- track calls
# through a file instead, matching scope_recovery_counter_file's pattern further below.
lpstat_call_counter_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-lpstat-count.XXXXXX")
printf '0' >"$lpstat_call_counter_file"
lpstat() {
  local n
  n=$(<"$lpstat_call_counter_file")
  n=$((n + 1))
  printf '%s' "$n" >"$lpstat_call_counter_file"
  if (( n >= 3 )); then
    printf 'scheduler is running\n'
  else
    printf 'lpstat: Unable to connect to cupsd\n'
    return 1
  fi
}
wait_for_cups_ready
[[ "$(<"$lpstat_call_counter_file")" -eq 3 ]]

printf '0' >"$lpstat_call_counter_file"
lpstat() {
  local n
  n=$(<"$lpstat_call_counter_file")
  n=$((n + 1))
  printf '%s' "$n" >"$lpstat_call_counter_file"
  printf 'lpstat: Unable to connect to cupsd\n'
  return 1
}
never_ready_output=$(wait_for_cups_ready 2>&1) || never_ready_status=$?
[[ "$never_ready_status" -ne 0 ]]
# 5 retry attempts plus one final unpiped call to capture the failure output for the error line.
[[ "$(<"$lpstat_call_counter_file")" -eq 6 ]]
[[ "$never_ready_output" == *'Unable to connect to cupsd'* ]]
rm -f "$lpstat_call_counter_file"

unset -f lpstat sleep step_check remote
grep -q 'wait_for_cups_ready' "$root/scripts/lib/onboarding/device-discovery.sh"
start_cups_block=$(awk '
  /Start CUPS for endpoint discovery/ { capturing = 1 }
  capturing { print }
  capturing && /CUPS endpoint discovery without ipp-usb/ { exit }
' "$root/scripts/lib/onboarding/device-discovery.sh")
[[ "$start_cups_block" == *'wait_for_cups_ready'* ]]

# WSD (the protocol this repo's own tested Brother MFC-7360N uses for AirScan, per
# docs/guides/brother-scanners.md) discovers devices via a multicast probe/response cycle with
# inherently variable timing. Reproduced live: running scanimage -L standalone on the Pi found
# the scanner every time, but discover_devices' single attempt found it roughly every other run
# -- and even 3 retries (2s apart) still occasionally came back empty in a later live run.
# scan_for_scanners retries up to 5 times with no added pause between attempts (each
# scanimage -L invocation already blocks for its own WSD response window, so extra sleep only
# adds wall-clock time without improving odds), showing the attempt number in the step label so
# a run that needs several attempts doesn't look stuck.
#
# This repo is general-purpose, not tuned to any one operator's hardware, so it must not assume
# only one scanner is ever connected: an earlier version returned as soon as any candidate was
# found, which would silently miss a second scanner that only answers a later WSD probe. Instead
# scan_for_scanners always runs all 5 attempts and merges (deduplicated) results across them, so
# a device that only answers on attempt 4 is still captured even if a different device already
# answered on attempt 1.
scanner_step_check_calls=0
scanner_step_check_purposes=()
step_check() {
  scanner_step_check_calls=$((scanner_step_check_calls + 1))
  local output_var=$1
  scanner_step_check_purposes+=("$2")
  case "$scanner_step_check_calls" in
    1) printf -v "$output_var" '%s' $'device `airscan:w0:Brother MFC-7360N\' is a WSD Brother MFC-7360N ip=192.168.50.2' ;;
    3) printf -v "$output_var" '%s' $'device `airscan:e0:Second Scanner\' is a WSD Second Scanner ip=192.168.178.40' ;;
    *) printf -v "$output_var" '%s' '' ;;
  esac
  return 0
}
sleep() { printf 'sleep called: %s\n' "$1" >&2; return 0; }
scanner_output=''
scan_for_scanners
# Runs every attempt rather than stopping at the first find, so a device that only answers on a
# later probe (here, attempt 3) is not silently dropped just because an earlier one succeeded.
[[ "$scanner_step_check_calls" -eq 5 ]]
[[ "${scanner_step_check_purposes[0]}" == *'attempt 1/5'* ]]
[[ "${scanner_step_check_purposes[4]}" == *'attempt 5/5'* ]]
merged_candidates=$(sane_scanner_candidates "$scanner_output")
[[ "$merged_candidates" == *'airscan:w0:Brother MFC-7360N'* ]]
[[ "$merged_candidates" == *'airscan:e0:Second Scanner'* ]]

scanner_step_check_calls=0
scanner_step_check_purposes=()
sleep_calls=0
step_check() {
  scanner_step_check_calls=$((scanner_step_check_calls + 1))
  local output_var=$1
  scanner_step_check_purposes+=("$2")
  printf -v "$output_var" '%s' ''
  return 0
}
sleep() { sleep_calls=$((sleep_calls + 1)); }
scanner_output=''
scan_for_scanners
[[ "$scanner_step_check_calls" -eq 5 ]]
[[ "${scanner_step_check_purposes[4]}" == *'attempt 5/5'* ]]
# No added pause between attempts -- each scanimage -L call already blocks on its own WSD
# response window, so an extra sleep would only add wall-clock time without improving odds.
[[ "$sleep_calls" -eq 0 ]]

unset -f sleep step_check
grep -q 'scan_for_scanners()' "$root/scripts/lib/onboarding/device-discovery.sh"
grep -Fq "step_check scanner_output \"Run SANE scanner discovery command (attempt \$attempt/5)\" 'scanimage -L' remote 'airscan-discover 2>&1; scanimage -L 2>&1'" \
  "$root/scripts/lib/onboarding/device-discovery.sh"
grep -q 'scan_for_scanners$' "$root/scripts/lib/onboarding/device-discovery.sh"

# discover_devices no longer declares printer_candidates/scanner_candidates locally -- it must
# append to whatever arrays are already declared in the caller's scope (global in
# scripts/onboard/scripts/manage-devices), so state (including candidates found by
# collect_direct_ethernet_link mid-loop) survives across separate top-level calls, not just
# discover_devices' own internal rerun recursion. The tools_ready parameter shifts from
# position 5 to position 3 once the previous_printer_candidates/previous_scanner_candidates
# parameters are removed.
global_array_block=$(awk '/^discover_devices\(\) \{/{capturing=1} capturing{print} capturing && /^  \[\[ "\$discovery_scope" != skip \]\]/{exit}' "$root/scripts/lib/onboarding/device-discovery.sh")
if [[ "$global_array_block" == *'local -a printer_candidates'* ]]; then
  printf "discover_devices must not shadow the caller's printer_candidates/scanner_candidates with local arrays\n" >&2
  exit 1
fi
[[ "$global_array_block" != *'previous_printer_candidates'* ]]
[[ "$global_array_block" == *'tools_ready=${3:-false}'* ]]

# A LAN/all-scope run that finds at least one device should offer to rerun discovery to look
# for more -- network discovery (WSD/AirScan in particular) can miss a device on one pass and
# find it, or a different one, on the next (reproduced live for the scanner side). This repo is
# general-purpose and must not assume a setup has only one printer or one scanner. USB-only
# scope is excluded since USB enumeration is deterministic, not flaky. A full miss on both is
# left to the "no devices found" recovery further down.
rerun_offer_block=$(awk '
  /Offer to rerun discovery whenever at least one device was found/ { capturing = 1 }
  capturing { print }
  capturing && /^  fi$/ { exit }
' "$root/scripts/lib/onboarding/device-discovery.sh")
[[ -n "$rerun_offer_block" ]]
[[ "$rerun_offer_block" == *'discovery_scope" != usb'* ]]
# Restricted to a full (both-kinds) discovery pass: a discovery_kind-narrowed run (e.g.
# select_or_collect_device's "search for more") must not offer a meaningless rerun for a device
# kind it never searches for.
[[ "$rerun_offer_block" == *'discovery_kind:-all}" == all'* ]]
# Fires whenever at least one device was found (not only on a partial miss), since even a fully
# successful pass might be missing a second device of the same kind.
[[ "$rerun_offer_block" == *'${#printer_candidates[@]} > 0 || ${#scanner_candidates[@]} > 0'* ]]
# Uses yes (default no), not yes_default, so a single-device success does not force an extra
# prompt on the common case -- rerunning is opt-in.
[[ "$rerun_offer_block" == *"yes 'Rerun discovery to search for additional or missed devices?"* ]]
[[ "$rerun_offer_block" != *"yes_default 'Rerun discovery"* ]]
# No positional candidate dump is needed on the recursive self-call any more -- the arrays are
# already global, so they carry the state forward without being threaded through as arguments.
[[ "$rerun_offer_block" == *'discover_devices true "$discovery_scope" true'* ]]
if [[ "$rerun_offer_block" == *'printf '\''%s\n'\'' "${printer_candidates[@]}"'* ]]; then
  printf 'rerun self-call must not re-pass candidates positionally now that the arrays are global\n' >&2
  exit 1
fi

# Discovery tools (apt-get update/install, real non-trivial work) must not be reinstalled on
# every rerun/retry that continues a pass which already installed them successfully -- only a
# call starting genuinely fresh, or retrying after an install failure, should attempt install.
grep -Fq 'local tools_ready=${3:-false}' "$root/scripts/lib/onboarding/device-discovery.sh"
grep -Fq 'if [[ "$tools_ready" != true ]]; then' "$root/scripts/lib/onboarding/device-discovery.sh"
# The rerun offer and the "no devices found" retry/scope recovery both continue a pass that
# already installed tools, so each must explicitly pass tools_ready=true.
grep -Fq 'discover_devices true "$discovery_scope" true; return $? ;;' "$root/scripts/lib/onboarding/device-discovery.sh"
# The install-failure retry/scope recovery (a genuine failure, not a continuation) must still
# attempt a real install -- it must not pass tools_ready=true.
install_failure_block=$(awk '
  /Discovery tools could not be installed/ { capturing = 1 }
  capturing { print }
  capturing && /^  fi$/ { exit }
' "$root/scripts/lib/onboarding/device-discovery.sh")
[[ "$install_failure_block" == *'discover_devices true "$discovery_scope"; return $? ;;'* ]]
if [[ "$install_failure_block" == *'discover_devices true "$discovery_scope" true'* ]]; then
  printf 'install-failure retry/scope must not skip a genuine reinstall attempt\n' >&2
  exit 1
fi

# Selection ("which detected printer/scanner do you want") is not done inside discover_devices
# any more -- it belongs to select_or_collect_device, which runs once per loop iteration
# instead of once per discover_devices call. discover_devices itself only searches and records
# candidates; the recovery check at the end is "no candidates were found at all", not "nothing
# was selected".
end_of_function_block=$(awk '
  /Discovery completed:.*printer candidate/ { capturing = 1 }
  capturing { print }
' "$root/scripts/lib/onboarding/device-discovery.sh")
if [[ "$end_of_function_block" == *'choose_candidate'* ]]; then
  printf 'discover_devices must not prompt for device selection; that belongs to select_or_collect_device\n' >&2
  exit 1
fi
[[ "$end_of_function_block" == *'${#printer_candidates[@]} == 0 && ${#scanner_candidates[@]} == 0'* ]]

# collect_direct_ethernet_link must exist as a standalone function, not be inlined into
# scripts/onboard's printer topology branch, so both collect_printer_definition and
# collect_scanner_definition (Tasks 6/7) can call it.
grep -q '^collect_direct_ethernet_link() {' "$root/scripts/lib/onboarding/device-discovery.sh"

# A failed direct_ethernet attempt must release direct_ethernet_interface (so another device
# can still claim the topology) and return non-zero, never exit the whole process -- other
# devices may already be successfully added to the loop by the time this one fails.
discover_direct_ethernet_device() { return 1; }
ask_detected() { printf 'eth1'; }
ask() { printf '%s' "$2"; }
valid_ipv4_cidr() { return 0; }
same_direct_ipv4_link() { return 0; }
recommendation() { :; }
direct_ethernet_interface=''
direct_ethernet_pi_ipv4_cidr=''
direct_ethernet_device_ipv4=''
scanner_candidates=()
printer_candidates=()
if collect_direct_ethernet_link; then
  printf 'collect_direct_ethernet_link must return non-zero when the underlying probe fails\n' >&2
  exit 1
fi
[[ -z "$direct_ethernet_interface" ]] || { printf 'a failed direct_ethernet attempt must release direct_ethernet_interface\n' >&2; exit 1; }
unset -f ask_detected ask valid_ipv4_cidr same_direct_ipv4_link recommendation
# discover_direct_ethernet_device was shadowed by the mock above; unset -f would remove it
# entirely rather than restoring the real sourced version, so re-source the library instead.
source "$root/scripts/lib/onboarding/device-discovery.sh"

# A scanner found as a side effect of a printer's direct_ethernet probe (or vice versa) must
# land in scanner_candidates[]/printer_candidates[], not a single-slot discovered_scanner_*
# variable, so it is visible to select_or_collect_device's "offer remaining candidates" step.
direct_ethernet_scanner_block=$(awk '/^  step_check scanner_output .Probe the direct device for scanning./{capturing=1} capturing{print} capturing && /^  fi$/{exit}' "$root/scripts/lib/onboarding/device-discovery.sh")
[[ "$direct_ethernet_scanner_block" == *'scanner_candidates+=("$candidate")'* ]]
if [[ "$direct_ethernet_scanner_block" == *'discovered_scanner=true'* ]]; then
  printf 'direct_ethernet scanner discovery must append to scanner_candidates, not set discovered_scanner\n' >&2
  exit 1
fi

# The primary printer's connection topology (network/direct_ethernet/usb) must never clear a
# separately-discovered scanner. A multifunction device commonly uses a different connection per
# function -- e.g. this repo's own tested Brother MFC-7360N prints over USB but scans over the
# network via AirScan (docs/guides/brother-scanners.md). Topology/connection/URI/USB collection
# now lives entirely in the shared collect_printer_definition (device-decisions.sh, covered by
# test/onboarding_device_decisions_test.sh) -- scripts/onboard must not inline its own copy of
# that logic (which is exactly what produced the original bug) or clear a scanner explicitly.
if grep -Fq 'discovered_scanner=false' "$root/scripts/onboard"; then
  printf 'scripts/onboard must not clear a separately-discovered scanner\n' >&2
  exit 1
fi
if grep -Eq "ask_choice 'How is this device connected" "$root/scripts/onboard"; then
  printf 'printer/scanner topology collection must go through the shared collect_printer_definition/collect_scanner_definition, not an inline copy in scripts/onboard\n' >&2
  exit 1
fi

probe_calls=0
step_check() { probe_calls=$((probe_calls + 1)); return 0; }
verify_ipp_listener_ready false
[[ "$probe_calls" -eq 0 ]]

step_check() {
  local output_var=$1
  printf -v "$output_var" '%s' "$mock_ipp_listener"
  return "$mock_ipp_listener_status"
}
mock_ipp_listener_status=1
mock_ipp_listener=''
not_listening=$(verify_ipp_listener_ready true 2>&1) || true
[[ "$not_listening" == *'not listening on TCP port 631'* ]]

mock_ipp_listener_status=0
mock_ipp_listener='LISTEN 0 128 127.0.0.1:631 0.0.0.0:*'
loopback_only=$(verify_ipp_listener_ready true 2>&1) || true
[[ "$loopback_only" == *'only on a loopback address'* ]]

mock_ipp_listener='LISTEN 0 128 0.0.0.0:631 0.0.0.0:*'
lan_facing=$(verify_ipp_listener_ready true)
[[ "$lan_facing" == *'trusted LAN'* ]]

mock_ipp_listener='LISTEN 0 128 [::]:631 [::]:*'
lan_facing_v6=$(verify_ipp_listener_ready true)
[[ "$lan_facing_v6" == *'trusted LAN'* ]]

grep -q 'verify_ipp_listener_ready true' "$root/scripts/onboard"

probe_calls=0
step_check() { probe_calls=$((probe_calls + 1)); return 0; }
verify_dns_sd_name_advertised false haak-drucker
[[ "$probe_calls" -eq 0 ]]

step_check() {
  local output_var=$1
  printf -v "$output_var" '%s' "$mock_avahi_output"
  return "$mock_avahi_status"
}
mock_avahi_status=1
mock_avahi_output=''
query_failed=$(verify_dns_sd_name_advertised true haak-drucker 2>&1) || true
[[ "$query_failed" == *'Could not query Avahi'* ]]

mock_avahi_status=0
mock_avahi_output='=;eth0;IPv4;other-queue;_ipp._tcp;local'
wrong_name=$(verify_dns_sd_name_advertised true haak-drucker 2>&1) || true
[[ "$wrong_name" == *'did not advertise'* ]]

mock_avahi_output='=;eth0;IPv4;haak-drucker;_ipp._tcp;local'
advertised=$(verify_dns_sd_name_advertised true haak-drucker)
[[ "$advertised" == *'haak-drucker'* && "$advertised" == *'advertised'* ]]

# CUPS always appends " @ <hostname>" to the advertised DNS-SD service name -- confirmed live,
# it never advertises the bare dns_sd_name on its own -- so an exact-match-only check against
# ";$dns_sd_name;" can never succeed and always reports a false "did not advertise".
mock_avahi_output='=;eth0;IPv4;haak-drucker @ haak-print-scan-server;_ipp._tcp;local'
advertised_with_hostname=$(verify_dns_sd_name_advertised true haak-drucker)
[[ "$advertised_with_hostname" == *'haak-drucker'* && "$advertised_with_hostname" == *'advertised'* ]]

mock_avahi_output='=;eth0;IPv4;other-queue @ haak-print-scan-server;_ipp._tcp;local'
wrong_name_with_hostname=$(verify_dns_sd_name_advertised true haak-drucker 2>&1) || true
[[ "$wrong_name_with_hostname" == *'did not advertise'* ]]

grep -q 'verify_dns_sd_name_advertised' "$root/scripts/onboard"

grep -q 'manual_recovery_command "$root" "$variables" "$inventory" playbooks/site.yml -e print_server_commissioning=true' "$root/scripts/onboard"
grep -q 'manual_recovery_command "$root" "$variables" "$inventory" playbooks/site.yml -e "print_server_commissioning=$commissioning"' "$root/scripts/manage-devices"

grep -q "ask_choice 'Enable page splitting" "$root/scripts/manage-devices"
grep -q -- '--page-splitting' "$root/scripts/manage-devices"
grep -Fq "ask_choice 'Enable page splitting (one PDF per scanned page)? (true, false)'" "$root/scripts/manage-devices"

# Task 10: manage-devices' configure_printer/configure_scanner adopt the same shared
# collect_printer_definition/collect_scanner_definition collectors onboard uses, gaining
# direct_ethernet topology support (previously available only from scripts/onboard's primary
# printer flow) instead of maintaining their own separate inline connection-collection copy.
configure_printer_block=$(awk '/^configure_printer\(\) \{/{capturing=1} capturing{print} capturing && /^\}$/{exit}' "$root/scripts/manage-devices")
[[ "$configure_printer_block" == *'collect_printer_definition'* ]]
if [[ "$configure_printer_block" == *"ask_choice 'Printer connection (LAN/direct IP protocol or USB)'"* ]]; then
  printf 'configure_printer must route connection collection through collect_printer_definition, not its own inline ask_choice\n' >&2
  exit 1
fi
grep -q 'direct_ethernet' "$root/scripts/manage-devices"

configure_scanner_block=$(awk '/^configure_scanner\(\) \{/{capturing=1} capturing{print} capturing && /^\}$/{exit}' "$root/scripts/manage-devices")
[[ "$configure_scanner_block" == *'collect_scanner_definition'* ]]

# manage-devices' configure_scanner also collects and persists the friendly display name added
# to select_or_collect_scanner, defaulting to the existing definition's display_name on edit.
[[ "$configure_scanner_block" == *"ask 'Friendly scanner name'"* ]]
[[ "$configure_scanner_block" == *'--display-name'* ]]
[[ "$configure_scanner_block" == *"field scanner \"\$original\" display_name"* ]]

grep -q "ask_choice 'Enable page splitting" "$root/scripts/lib/onboarding/device-decisions.sh"
grep -q 'scanservjs_page_splitting:' "$root/scripts/onboard"
grep -Fq "ask_choice 'Enable page splitting (one PDF per scanned page)? (true, false)'" "$root/scripts/lib/onboarding/device-decisions.sh"

# Ticket 017: create_scanner_test_pdf drives scanimage and convert through
# remote(), enforces test -s on the resulting PDF, and always cleans up its
# temporary PNG. Mock remote() to actually evaluate the generated command
# locally, with fake scanimage/convert standing in for the real tools, so the
# three real outcomes (success, SANE failure, empty output) can be observed.
step_action() {
  local output_variable=$1
  shift 3
  local output status
  output=$("$@" 2>&1) && status=0 || status=$?
  printf -v "$output_variable" '%s' "$output"
  return "$status"
}
remote() { eval "$1"; }

scan_index="test-$$"
scan_pdf="/var/tmp/scanservjs-onboarding-test-$scan_index.pdf"
scan_png="/var/tmp/scanservjs-onboarding-test-$scan_index.png"
rm -f "$scan_pdf" "$scan_png"

# Successful scan: scanimage and convert both succeed, the PDF is non-empty
# and the intermediate PNG is removed.
scanimage() { printf 'PNGDATA'; return "$mock_scanimage_status"; }
convert() { [[ "$mock_convert_writes_content" == true ]] && printf 'PDFDATA' >"$2"; return "$mock_convert_status"; }
mock_scanimage_status=0
mock_convert_status=0
mock_convert_writes_content=true
if create_scanner_test_pdf 'airscan:e0:Office Scanner' "$scan_index" >/dev/null 2>&1; then success_status=0; else success_status=$?; fi
[[ "$success_status" -eq 0 ]]
[[ -s "$scan_pdf" ]]
[[ ! -e "$scan_png" ]]
rm -f "$scan_pdf"

# SANE failure: scanimage itself fails, so convert never runs and no PDF is
# ever claimed as created.
mock_scanimage_status=1
mock_convert_status=0
mock_convert_writes_content=true
if sane_failure=$(create_scanner_test_pdf 'airscan:e0:Office Scanner' "$scan_index" 2>&1); then sane_failure_status=0; else sane_failure_status=$?; fi
[[ "$sane_failure_status" -ne 0 ]]
[[ "$sane_failure" == *'did not produce a usable PDF'* ]]
[[ ! -e "$scan_pdf" ]]
[[ ! -e "$scan_png" ]]

# Empty output: scanimage exits 0 but convert produces no usable PDF, so the
# test -s guard on the final PDF catches it.
mock_scanimage_status=0
mock_convert_status=0
mock_convert_writes_content=false
if empty_output=$(create_scanner_test_pdf 'airscan:e0:Office Scanner' "$scan_index" 2>&1); then empty_output_status=0; else empty_output_status=$?; fi
[[ "$empty_output_status" -ne 0 ]]
[[ "$empty_output" == *'did not produce a usable PDF'* ]]
[[ ! -e "$scan_pdf" ]]
[[ ! -e "$scan_png" ]]

unset -f scanimage convert

# Ticket 010: the scanner-test-PDF summary in scripts/onboard previously reported
# the total scanner count as the number created even when some failed. Extract
# the exact loop (same technique as test/onboarding_retry_inventory_safety_test.sh)
# and drive it with a mocked create_scanner_test_pdf that fails for one of two
# scanners, asserting the printed count reflects actual successes.
onboard_scan_loop=$(awk '
  /Create scanner test PDFs now/ { capturing = 1 }
  capturing { print }
  capturing && /^fi$/ { exit }
' "$root/scripts/onboard")
[[ -n "$onboard_scan_loop" ]]
[[ "$onboard_scan_loop" == *'scanner_test_pdfs_created'* ]]

yes() { return 0; }
create_scanner_test_pdf() { [[ "$1" == 'good-scanner' ]]; }
scanner_device_names=(good-scanner bad-scanner)
host=print-server.local
partial_success_output=$(eval "$onboard_scan_loop")
[[ "$partial_success_output" == 'Created 1 of 2 scanner test PDF(s) under /var/tmp on print-server.local.' ]]
unset -f yes create_scanner_test_pdf

source "$root/scripts/lib/onboarding/prompts.sh"

printer_candidate_output=$(printer_candidate_details \
  'USB printer (usb://Brother/MFC-7360N?serial=E69717C5N288928)|usb|usb://Brother/MFC-7360N?serial=E69717C5N288928|legacy_usb' \
  'Network printer (ipp://192.0.2.20/ipp/print)|ipp|ipp://192.0.2.20/ipp/print|' 2>&1)
[[ "$printer_candidate_output" == *'Candidate 1'* ]]
[[ "$printer_candidate_output" == *'USB printer (usb://Brother/MFC-7360N?serial=E69717C5N288928)'* ]]
[[ "$printer_candidate_output" == *'usb://Brother/MFC-7360N?serial=E69717C5N288928'* ]]
[[ "$printer_candidate_output" == *'legacy_usb'* ]]
[[ "$printer_candidate_output" == *'Candidate 2'* ]]

scanner_candidate_output=$(scanner_candidate_details 'airscan:e0:Office Scanner (SANE AirScan detected)|ipp|sane-airscan||airscan:e0:Office Scanner' 2>&1)
[[ "$scanner_candidate_output" == *'Candidate 1'* ]]
[[ "$scanner_candidate_output" == *'sane-airscan'* ]]
[[ "$scanner_candidate_output" == *'airscan:e0:Office Scanner'* ]]

# printer_candidate_details/scanner_candidate_details are called from select_or_collect_device
# (device-decisions.sh) now that selection has moved out of discover_devices; see Task 8's
# coverage in test/onboarding_device_decisions_test.sh.

# Finding 2: the final review screen must recap every collected field through
# confirmation_block, not a hand-written printf, since it is the last thing shown
# before production inventory is written and Ansible provisioning starts.
review_block=$(awk '
  /^stage .5 of 5. .Review and commission./ { capturing = 1 }
  capturing { print }
  capturing && /Write production inventory and commission this Pi/ { exit }
' "$root/scripts/onboard")
[[ -n "$review_block" ]]
[[ "$review_block" == *"confirmation_block 'Server'"* ]]
[[ "$review_block" == *'confirmation_block "Printer:'* ]]
[[ "$review_block" == *'confirmation_block "Scanner:'* ]]
[[ "$review_block" == *"confirmation_block 'ScanservJS'"* ]]
for field in hostname timezone locale ipv6_cidr direct_ethernet_interface authorized_key \
  printer_connections printer_uris printer_drivers printer_usb_modes printer_usb_identities \
  scanner_backends scanner_backend_installs scanner_usb_modes scanner_usb_identities \
  scanner_display_names page_splitting; do
  if [[ "$review_block" != *"\$$field"* && "$review_block" != *"\${$field"* ]]; then
    printf 'Review screen never references %s\n' "$field" >&2
    exit 1
  fi
done

# A scanner's friendly display name is written to inventory only when it differs from the exact
# SANE device name, matching the dns_sd_name-only-if-different convention already used for
# printers -- writing it unconditionally would duplicate the device name in the common case.
yaml_write_block=$(awk '
  /^  if \(\( \$\{#scanner_device_names\[@\]\} > 0 \)\); then$/ { capturing = 1 }
  capturing { print }
  capturing && /^  else$/ { exit }
' "$root/scripts/onboard")
[[ -n "$yaml_write_block" ]]
[[ "$yaml_write_block" == *'display_name'* ]]
[[ "$yaml_write_block" == *'scanner_display_names[$index]'* ]]
if [[ "$yaml_write_block" != *'!= "${scanner_device_names[$index]}"'* ]]; then
  printf 'scanner display_name must only be written when it differs from the device name\n' >&2
  exit 1
fi

# Finding 10: the driverless/package_profile explanation only makes sense next to the prompt
# that actually asks it (the non-USB else branch) -- the USB branch derives driver mode
# directly from usb_mode and never shows the ask_choice at all. This now lives in the shared
# select_or_collect_printer (device-decisions.sh), the only place that asks it.
driver_mode_block=$(awk '/^select_or_collect_printer\(\) \{/{capturing=1} capturing{print} capturing && /^\}$/{exit}' "$root/scripts/lib/onboarding/device-decisions.sh")
[[ "$driver_mode_block" == *'else'*'Choose driverless first'* ]]
if grep -Eq "ask_choice 'Printer driver mode'" "$root/scripts/onboard"; then
  printf 'printer driver mode collection must go through the shared select_or_collect_printer, not an inline copy in scripts/onboard\n' >&2
  exit 1
fi

# Finding 11/F: the preinstalled-backend contradiction ("will not install... it" immediately
# followed by a prompt offering to do exactly that) can no longer exist structurally: every
# scanner, discovered-preinstalled or not, now routes through the single
# collect_scanner_definition path, which always calls collect_scanner_backend/
# scanner_backend_guidance and keeps a discovered backend_install=false as its default rather
# than special-casing it with different wording.
if grep -Fq 'will not install, update or register it' "$root/scripts/onboard" "$root/scripts/lib/onboarding/device-decisions.sh"; then
  printf 'the preinstalled-backend contradiction text must not reappear\n' >&2
  exit 1
fi
grep -Fq 'collect_scanner_backend "$connection"' "$root/scripts/lib/onboarding/device-decisions.sh"

# Finding C: scanner USB mode must be explained before being asked, in every collection path
# that asks it -- mirroring the printer path's USB-mode explanation. USB mode collection now
# lives entirely in the shared collect_scanner_definition (one site), so scripts/onboard must
# not have its own copy of the prompt at all.
grep -q 'scanner_usb_mode_guidance' "$root/scripts/lib/onboarding/device-decisions.sh"
if grep -q "ask_choice 'Scanner USB mode'" "$root/scripts/onboard"; then
  printf 'scanner USB mode must be asked only inside the shared collect_scanner_definition, not inline in onboard\n' >&2
  exit 1
fi
device_decisions_scanner_usb_mode_sites=$(grep -c "ask_choice 'Scanner USB mode'" "$root/scripts/lib/onboarding/device-decisions.sh")
[[ "$device_decisions_scanner_usb_mode_sites" -eq 1 ]]
# manage-devices' configure_scanner now delegates connection/backend/USB-mode/USB-identity
# collection to the same shared collect_scanner_definition (Task 10), so it must not have its
# own inline copy of the USB-mode prompt or guidance any more.
scanner_config_block=$(awk '/^configure_scanner\(\) \{/{capturing=1} capturing{print} capturing && /^\}$/{exit}' "$root/scripts/manage-devices")
[[ "$scanner_config_block" == *'collect_scanner_definition'* ]]
if [[ "$scanner_config_block" == *"ask_choice 'Scanner connection (network, ipp, ipps or USB)'"* ]]; then
  printf 'configure_scanner must route connection collection through collect_scanner_definition, not its own inline ask_choice\n' >&2
  exit 1
fi

# Finding D: onboard must collect a USB identity for every scanner, matching what
# manage-devices already does, instead of silently leaving it unset for scanners configured
# during first-run onboarding.
grep -q 'scanner_usb_identities' "$root/scripts/onboard"
grep -Fq '${scanner_usb_identities[$index]}' "$root/scripts/onboard"

# Finding E: manage-devices must validate a scanner's USB identity the same way it already
# validates a printer's, instead of accepting any string unchecked -- now guaranteed structurally
# since collect_scanner_definition (device-decisions.sh) is the single site collecting it.
grep -Fq 'valid_usb_identity' "$root/scripts/lib/onboarding/device-decisions.sh"

# Finding 5/6: every device (first or additional, printer or scanner) must give the same
# guidance and confirm the finished definition at the end -- the unified loop replaces the old
# asymmetric "primary + separate additional loop" and "primary + separate optional scanner"
# mechanisms with a single call site per device type through select_or_collect_device.
loop_block=$(awk '
  /^stage .4 of 5. .Choose your devices./ { capturing = 1 }
  capturing { print }
  capturing && /^stage .5 of 5. .Review and commission./ { exit }
' "$root/scripts/onboard")
[[ -n "$loop_block" ]]
[[ "$loop_block" == *'select_or_collect_device "$action"'* ]]
[[ "$loop_block" == *"ask_choice 'Add a device?"* ]]
if [[ "$loop_block" == *"while yes 'Add another printer?'"* ]]; then
  printf 'the separate "Add another printer?" loop must be replaced by the unified add-a-device loop\n' >&2
  exit 1
fi
if [[ "$loop_block" == *"'Configure a different scanner?'"* ]]; then
  printf 'the separate optional-scanner gate must be replaced by the unified add-a-device loop\n' >&2
  exit 1
fi
[[ "$loop_block" == *'At least one device is required'* ]]
grep -q 'printer_connection_confirmation "\$queue"' "$root/scripts/lib/onboarding/device-decisions.sh"
grep -q 'confirmation_block "Scanner: \$device_name"' "$root/scripts/lib/onboarding/device-decisions.sh"

# Finding 8: the retention/OCR/port guidance sentences the review named specifically must use
# the recommendation heading like other suggested-default-with-a-reason guidance, not unmarked
# prose that a skimming reader can't distinguish from narration. This now lives in the shared
# collect_scanservjs_settings (device-decisions.sh), the only place that asks it.
grep -Fq "recommendation 'Choose 90 days as a starting point" "$root/scripts/lib/onboarding/device-decisions.sh"
grep -Fq "recommendation 'OCR makes scanned PDFs searchable" "$root/scripts/lib/onboarding/device-decisions.sh"
grep -Fq "recommendation 'The ScanservJS port is the local TCP port" "$root/scripts/lib/onboarding/device-decisions.sh"

# Finding 12: cli_color must gate on stderr (the descriptor every caller actually writes to),
# not stdout.
grep -Fq -- '-t 2 &&' "$root/scripts/lib/onboarding/prompts.sh"
if grep -Fq -- '-t 1 &&' "$root/scripts/lib/onboarding/prompts.sh"; then
  printf 'cli_color still gates on stdout terminal-ness\n' >&2
  exit 1
fi

# Finding 14: the step-3 major-step purpose already states discovery covers the trusted LAN
# and USB devices; device-discovery.sh must not restate the same fact moments later.
if grep -Fq 'Discovery can find printers and scanners that are visible on the trusted LAN or connected by USB.' "$root/scripts/lib/onboarding/device-discovery.sh"; then
  printf 'device-discovery.sh restates the step-3 purpose sentence\n' >&2
  exit 1
fi

# Finding 15: the five-step intro's caveats must be visually separated from the numbered list,
# and must restate the explicit guarantee that production inventory/queues/services change
# only after final confirmation (present in the original wording, dropped when the legacy-driver
# caveat was added).
intro_block=$(awk '/This guided setup has five steps/{capturing=1} capturing{print} capturing && /Production inventory/{exit}' "$root/scripts/onboard")
[[ -n "$intro_block" ]]
[[ "$intro_block" == *"is changed.' \\"$'\n'"  '' \\"* ]]
[[ "$intro_block" == *'Production inventory, queues and services are changed only after final confirmation.'* ]]

# Finding 16: step numbering must match the design spec's own wording ('N of 5', sentence
# case), which is also what test/onboarding_prompts_test.sh already asserts major_step on.
[[ "$(grep -c "^stage '[0-9] of 5'" "$root/scripts/onboard")" -eq 5 ]]
if grep -q "^stage '[0-9]/5'" "$root/scripts/onboard"; then
  printf 'onboard still uses N/5 step numbering instead of the spec wording\n' >&2
  exit 1
fi

variables="$root/inventories/production/group_vars/print_servers.yml"
backups="$root/.onboard-backups"
if [[ -x "$root/.venv/bin/python" ]]; then
  ONBOARD_PYTHON="$root/.venv/bin/python"
else
  ONBOARD_PYTHON=$(command -v python3)
fi

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

# Ticket 015 / Task 4: discover_devices reports candidates it finds through its global
# printer_candidates/scanner_candidates arrays and never prompts for a selection itself
# (that responsibility moved to select_or_collect_device) -- confirmed for a scoped
# discovery_kind (matching scripts/onboard's/manage-devices' "search for more" calls) and for
# the unscoped default alike.
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
choose_candidate() { printf 'choose_candidate must not be called from discover_devices\n' >&2; exit 1; }
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

printer_candidates=()
scanner_candidates=()
discovery_kind=printer
printer_scoped_output=$(discover_devices true all)
unset discovery_kind
[[ "$printer_scoped_output" == *'Discovery completed: 1 printer candidate(s), 1 scanner candidate(s).'* ]]

printer_candidates=()
scanner_candidates=()
discovery_kind=scanner
scanner_scoped_output=$(discover_devices true all)
unset discovery_kind
[[ "$scanner_scoped_output" == *'Discovery completed: 1 printer candidate(s), 1 scanner candidate(s).'* ]]

# Without discovery_kind set (the default 'all'), discovery still just finds and reports.
printer_candidates=()
scanner_candidates=()
unscoped_output=$(discover_devices true all)
[[ "$unscoped_output" == *'Discovery completed: 1 printer candidate(s), 1 scanner candidate(s).'* ]]

rm -f "${TMPDIR:-/tmp}"/raspberry-print-server-discovery.*.log

# Ticket 013: discover_direct_ethernet_device must offer a recovery menu
# (retry, change settings, continue manually, stop) on every failure branch,
# and must run direct_ethernet_discovery_cleanup (restore_ipp_usb_state,
# restore_cups_state, and any temporary nmcli connection delete) before every
# retry attempt so each attempt starts from a clean state.
direct_ethernet_interface=eth1
direct_ethernet_pi_ipv4_cidr=192.168.50.1/30
direct_ethernet_device_ipv4=192.168.50.2
yes() { return 0; }
recommendation() { :; }
technical_report() { :; }
tcp_port_is_open() { return 1; }

mock_interface_ok=true
mock_carrier_ok=true
mock_nmcli_ok=true
mock_ping_ok=true
recovery_choice_sequence=()
delete_calls=0
cleanup_ipp_calls=0
cleanup_cups_calls=0

# recovery_choice is invoked as `choice=$(recovery_choice ...)`, which forks a
# subshell; a plain shell-variable call counter would reset to zero on every
# invocation and the mock would return the same choice forever (infinite
# retry recursion). Persist the counter in a file instead, since filesystem
# state survives across subshells.
recovery_choice_counter_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-recovery-choice.XXXXXX")

step_check() {
  local output_variable=$1 label=$2
  case "$label" in
    'Verify the direct Ethernet interface')
      printf -v "$output_variable" ''
      [[ "$mock_interface_ok" == true ]]
      return
      ;;
    'Check the direct Ethernet cable carrier')
      printf -v "$output_variable" '%s' "$([[ "$mock_carrier_ok" == true ]] && printf 1 || printf 0)"
      return 0
      ;;
    'Reach the directly connected device')
      printf -v "$output_variable" ''
      [[ "$mock_ping_ok" == true ]]
      return
      ;;
    *)
      printf -v "$output_variable" ''
      return 1
      ;;
  esac
}
step_action() {
  local output_variable=$1
  printf -v "$output_variable" ''
  [[ "$mock_nmcli_ok" == true ]]
}
remote_tty() {
  [[ "$*" == *'nmcli connection delete'* ]] && delete_calls=$((delete_calls + 1))
  return 0
}
restore_ipp_usb_state() { cleanup_ipp_calls=$((cleanup_ipp_calls + 1)); }
restore_cups_state() { cleanup_cups_calls=$((cleanup_cups_calls + 1)); }
recovery_choice() {
  local n choice
  n=$(<"$recovery_choice_counter_file")
  choice=${recovery_choice_sequence[$n]}
  printf '%s' "$((n + 1))" >"$recovery_choice_counter_file"
  printf '%s' "$choice"
}

# Missing-interface retry: the interface check fails on every attempt. The
# operator retries once, then stops. Cleanup must run before both the retry
# and the stop, but no nmcli connection was ever created, so no delete is
# expected.
mock_interface_ok=false
printf '0' >"$recovery_choice_counter_file"
recovery_choice_sequence=(retry stop)
delete_calls=0
cleanup_ipp_calls=0
cleanup_cups_calls=0
missing_interface_status=0
discover_direct_ethernet_device >/dev/null 2>&1 || missing_interface_status=$?
[[ "$missing_interface_status" -eq 1 ]]
recovery_choice_calls=$(<"$recovery_choice_counter_file")
[[ "$recovery_choice_calls" -eq 2 ]]
[[ "$cleanup_ipp_calls" -eq 2 ]]
[[ "$cleanup_cups_calls" -eq 2 ]]
[[ "$delete_calls" -eq 0 ]]
mock_interface_ok=true

# No-carrier retry: the interface exists but the cable carrier check fails on
# every attempt. Same expectations: two recovery prompts, cleanup runs before
# each, and no nmcli connection was created.
mock_carrier_ok=false
printf '0' >"$recovery_choice_counter_file"
recovery_choice_sequence=(retry stop)
delete_calls=0
cleanup_ipp_calls=0
cleanup_cups_calls=0
no_carrier_status=0
discover_direct_ethernet_device >/dev/null 2>&1 || no_carrier_status=$?
[[ "$no_carrier_status" -eq 1 ]]
recovery_choice_calls=$(<"$recovery_choice_counter_file")
[[ "$recovery_choice_calls" -eq 2 ]]
[[ "$cleanup_ipp_calls" -eq 2 ]]
[[ "$cleanup_cups_calls" -eq 2 ]]
[[ "$delete_calls" -eq 0 ]]
mock_carrier_ok=true

# nmcli-configuration-failure retry: the interface and carrier checks pass but
# the temporary link configuration fails on every attempt. A temporary
# connection is created and must be deleted before each retry and again
# before stopping.
mock_nmcli_ok=false
printf '0' >"$recovery_choice_counter_file"
recovery_choice_sequence=(retry stop)
delete_calls=0
cleanup_ipp_calls=0
cleanup_cups_calls=0
nmcli_failure_status=0
discover_direct_ethernet_device >/dev/null 2>&1 || nmcli_failure_status=$?
[[ "$nmcli_failure_status" -eq 1 ]]
recovery_choice_calls=$(<"$recovery_choice_counter_file")
[[ "$recovery_choice_calls" -eq 2 ]]
[[ "$cleanup_ipp_calls" -eq 2 ]]
[[ "$cleanup_cups_calls" -eq 2 ]]
[[ "$delete_calls" -eq 2 ]]
[[ -z "$temporary_direct_connection" ]]
mock_nmcli_ok=true

# Ping-failure retry: the temporary link configures successfully but the
# device never answers. Same expectations as the nmcli failure: two deletes
# of the temporary connection, one per attempt.
mock_ping_ok=false
printf '0' >"$recovery_choice_counter_file"
recovery_choice_sequence=(retry stop)
delete_calls=0
cleanup_ipp_calls=0
cleanup_cups_calls=0
ping_failure_status=0
discover_direct_ethernet_device >/dev/null 2>&1 || ping_failure_status=$?
[[ "$ping_failure_status" -eq 1 ]]
recovery_choice_calls=$(<"$recovery_choice_counter_file")
[[ "$recovery_choice_calls" -eq 2 ]]
[[ "$cleanup_ipp_calls" -eq 2 ]]
[[ "$cleanup_cups_calls" -eq 2 ]]
[[ "$delete_calls" -eq 2 ]]
[[ -z "$temporary_direct_connection" ]]
mock_ping_ok=true

# Change-settings must return status 2 without recursing, so scripts/onboard
# can re-prompt the interface, CIDR and device address before calling again.
mock_interface_ok=false
printf '0' >"$recovery_choice_counter_file"
recovery_choice_sequence=(change)
change_status=0
discover_direct_ethernet_device >/dev/null 2>&1 || change_status=$?
[[ "$change_status" -eq 2 ]]
recovery_choice_calls=$(<"$recovery_choice_counter_file")
[[ "$recovery_choice_calls" -eq 1 ]]
mock_interface_ok=true

# Ticket 014: discover_direct_ethernet_device's scanner-probe step must accept
# a scanner candidate identified only by hostname when that hostname resolves
# exclusively, via the Raspberry Pi over the temporary link, to the configured
# direct device address. Drive the full temporary-link setup through cleanup,
# not just the isolated direct_scanner_candidate helper.
step_action() {
  local output_variable=$1
  printf -v "$output_variable" ''
  return 0
}
step_check() {
  local output_variable=$1 label=$2
  case "$label" in
    'Verify the direct Ethernet interface') printf -v "$output_variable" ''; return 0 ;;
    'Check the direct Ethernet cable carrier') printf -v "$output_variable" '1'; return 0 ;;
    'Reach the directly connected device') printf -v "$output_variable" ''; return 0 ;;
    'Probe the direct device for scanning') printf -v "$output_variable" '%s' "$mock_scanner_output"; return 0 ;;
    *) printf -v "$output_variable" ''; return 1 ;;
  esac
}
delete_calls=0
cleanup_ipp_calls=0
cleanup_cups_calls=0

# Exclusive resolution: the hostname resolves to exactly the configured
# direct device address, so the hostname-only candidate is accepted.
remote() {
  case "$*" in
    *'getent ahostsv4 printer.local'*) printf '192.168.50.2\n'; return 0 ;;
    *) return 0 ;;
  esac
}
mock_scanner_output=$'device `airscan:e0:printer.local\' is a scanner'
scanner_candidates=()
printer_candidates=()
direct_ethernet_output_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-direct-ethernet.XXXXXX")
# Redirect rather than use $(...): command substitution forks a subshell, and
# scanner_candidates is appended to as a global inside discover_direct_ethernet_device, so it
# must be observed in this shell, not a discarded subshell copy (same pitfall noted above for
# scope_calls).
discover_direct_ethernet_device >"$direct_ethernet_output_file" 2>&1
hostname_bound_output=$(<"$direct_ethernet_output_file")
[[ "${#scanner_candidates[@]}" -eq 1 ]]
[[ "${scanner_candidates[0]}" == *'airscan:e0:printer.local'* ]]
[[ "$hostname_bound_output" == *'Detected a scanner: airscan:e0:printer.local'* ]]
[[ "$delete_calls" -ge 1 ]]

# Ambiguous resolution: the hostname resolves to the configured address plus
# another, so it must never be treated as address-bound.
remote() {
  case "$*" in
    *'getent ahostsv4 printer.local'*) printf '192.168.50.2\n192.168.50.3\n'; return 0 ;;
    *) return 0 ;;
  esac
}
scanner_candidates=()
discover_direct_ethernet_device >"$direct_ethernet_output_file" 2>&1
ambiguous_output=$(<"$direct_ethernet_output_file")
[[ "${#scanner_candidates[@]}" -eq 0 ]]
[[ "$ambiguous_output" == *'No scanner identifier was bound'* ]]

# Failed resolution: the hostname does not resolve at all, so the candidate
# is rejected rather than assumed to be the direct device.
remote() {
  case "$*" in
    *'getent ahostsv4 printer.local'*) return 2 ;;
    *) return 0 ;;
  esac
}
scanner_candidates=()
discover_direct_ethernet_device >"$direct_ethernet_output_file" 2>&1
unresolved_output=$(<"$direct_ethernet_output_file")
[[ "${#scanner_candidates[@]}" -eq 0 ]]
[[ "$unresolved_output" == *'No scanner identifier was bound'* ]]
rm -f "$direct_ethernet_output_file"

# Ticket 013: discover_devices' recovery menu gains a "change scope" option
# that re-prompts the discovery scope (all/lan/usb/skip) and passes the new
# value into the retried recursive call. Wrap the real discover_devices to
# record the scope argument on every entry, including recursive re-entries
# triggered from inside the original function body.
eval "$(declare -f discover_devices | sed '1s/^discover_devices/discover_devices_original/')"
scope_calls=()
discover_devices() {
  scope_calls+=("${2:-all}")
  discover_devices_original "$@"
}

remote() {
  case "$*" in
    *'timeout 10s lpinfo -v'*) return 1 ;;
    *'sudo ipp-usb check'*) printf 'no IPP over USB devices found'; return 1 ;;
    *'scanimage -L'*) return 1 ;;
    *) return 0 ;;
  esac
}
remote_tty() { return 0; }
avahi_browse_scan() { return 0; }
choose_candidate() { printf 'manual'; }
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

# recovery_choice runs as `choice=$(recovery_choice ...)`, forking a subshell,
# so (as above) its call count must be tracked through a file rather than a
# plain shell variable.
scope_recovery_counter_file=$(mktemp "${TMPDIR:-/tmp}/raspberry-print-server-scope-recovery.XXXXXX")
printf '0' >"$scope_recovery_counter_file"
recovery_choice() {
  local n
  n=$(<"$scope_recovery_counter_file")
  printf '%s' "$((n + 1))" >"$scope_recovery_counter_file"
  if (( n == 0 )); then
    printf 'scope'
  else
    printf 'manual'
  fi
}
ask_choice() { printf 'usb'; }

# Call discover_devices as a plain statement rather than through $(...): a
# command substitution would fork a subshell too, and scope_calls (appended
# inside the discover_devices wrapper above) would never be visible here once
# that subshell exited.
printer_candidates=()
scanner_candidates=()
discover_devices true all >/dev/null 2>&1
scope_recovery_calls=$(<"$scope_recovery_counter_file")
[[ "$scope_recovery_calls" -eq 2 ]]
[[ "${#scope_calls[@]}" -eq 2 ]]
[[ "${scope_calls[0]}" == all ]]
[[ "${scope_calls[1]}" == usb ]]

unset -f discover_devices discover_devices_original recovery_choice ask_choice remote remote_tty avahi_browse_scan choose_candidate technical_report step_check step_action step_stream

rm -f "${TMPDIR:-/tmp}"/raspberry-print-server-discovery.*.log
