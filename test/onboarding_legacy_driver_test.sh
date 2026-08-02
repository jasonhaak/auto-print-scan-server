#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/legacy-driver.sh"

prepare_count=0
package_profile_model_prefix() { printf '%s' 'drv:///brlaser.drv/'; }
subsection() { :; }
yes_default() { return 0; }
remote() { return 0; }
step_stream() { ((++prepare_count)); return 0; }
step_check() {
  local output_variable=$1
  printf -v "$output_variable" '%s' 'drv:///brlaser.drv/br7360.ppd Brother MFC-7360N'
  return 0
}
choose_cups_model() { printf '%s' 'drv:///brlaser.drv/br7360.ppd'; }

legacy_driver_inventory=/tmp/inventory
ssh_socket=/tmp/socket
prepare_and_choose_cups_model brlaser 'usb://Brother/MFC-7360N?serial=one' 'Brother MFC-7360N'
[[ "$LEGACY_SELECTED_PACKAGE_PROFILE" == brlaser ]]
[[ "$LEGACY_SELECTED_CUPS_MODEL" == 'drv:///brlaser.drv/br7360.ppd' ]]
prepare_and_choose_cups_model brlaser 'usb://Brother/MFC-7360N?serial=two' 'Brother MFC-7360N'
[[ "$prepare_count" == 1 ]]
