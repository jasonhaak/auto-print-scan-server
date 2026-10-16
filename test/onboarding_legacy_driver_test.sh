#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/legacy-driver.sh"
source "$root/scripts/lib/onboarding/device-decisions.sh"

prepare_count=0
package_profile_model_prefix() { printf '%s' 'drv:///brlaser.drv/'; }
subsection() { :; }
yes_default() { return 0; }
remote() { return 0; }
step_stream() { ((++prepare_count)); if [[ -n "${LAST_PREPARE_INVOCATION:-}" ]]; then printf '%s\n' "$*" >"$LAST_PREPARE_INVOCATION"; fi; return 0; }
step_check() {
  local output_variable=$1
  printf -v "$output_variable" '%s' 'drv:///brlaser.drv/br7360.ppd Brother MFC-7360N'
  return 0
}
choose_cups_model() { printf '%s' 'drv:///brlaser.drv/br7360.ppd'; }
recommend_legacy_profile() { legacy_printer_identity_evidence='Brother MFC-7360N'; }
choose_package_profile() { printf '%s' "${1:-brlaser}"; }

legacy_driver_inventory=/tmp/inventory
ssh_socket=/tmp/socket
prepare_and_choose_cups_model brlaser 'usb://Brother/MFC-7360N?serial=one' 'Brother MFC-7360N'
[[ "$LEGACY_SELECTED_PACKAGE_PROFILE" == brlaser ]]
[[ "$LEGACY_SELECTED_CUPS_MODEL" == 'drv:///brlaser.drv/br7360.ppd' ]]
prepare_and_choose_cups_model brlaser 'usb://Brother/MFC-7360N?serial=two' 'Brother MFC-7360N'
[[ "$prepare_count" == 1 ]]

collect_legacy_printer_profile 'usb://Brother/MFC-7360N?serial=three' brlaser
[[ "$COLLECTED_PRINTER_PROFILE" == brlaser ]]
[[ "$COLLECTED_PRINTER_IDENTITY_EVIDENCE" == 'Brother MFC-7360N' ]]

LAST_PREPARE_INVOCATION=$(mktemp "${TMPDIR:-/tmp}/onboarding-legacy-prepare.XXXXXX")
unset 'LEGACY_PROFILE_MODELS[brlaser]'
CATALOG_SUITE=trixie CATALOG_ARCHITECTURE=armhf CATALOG_REPOSITORY=R \
  prepare_and_choose_cups_model brlaser 'ipp://printer/ipp/print' <<< '1' >/dev/null
grep -q '"package_architecture":"armhf"' "$LAST_PREPARE_INVOCATION" || {
  echo "catalog identity not forwarded to preparation" >&2; exit 1; }
rm -f "$LAST_PREPARE_INVOCATION"
