#!/usr/bin/env bash

collect_legacy_printer_profile() {
  local uri=$1 profile_default=${2:-}
  COLLECTED_PRINTER_IDENTITY_EVIDENCE=''
  recommend_legacy_profile "$uri"
  COLLECTED_PRINTER_IDENTITY_EVIDENCE=${legacy_printer_identity_evidence:-}
  COLLECTED_PRINTER_PROFILE=$(choose_package_profile "$profile_default")
}

prepare_legacy_printer_model() {
  local profile=$1 uri=$2 evidence=${3:-}
  prepare_and_choose_cups_model "$profile" "$uri" "$evidence" || return 1
  COLLECTED_PRINTER_PROFILE=$LEGACY_SELECTED_PACKAGE_PROFILE
  COLLECTED_PRINTER_CUPS_MODEL=$LEGACY_SELECTED_CUPS_MODEL
}

collect_scanner_backend() {
  local connection=$1 backend_default=$2 install_default=$3
  scanner_backend_guidance "$connection"
  COLLECTED_SCANNER_BACKEND=$(ask 'SANE backend name' "$backend_default")
  COLLECTED_SCANNER_BACKEND_INSTALL=$(ask_choice 'Install this backend package with APT' "$install_default" true false)
}

scanner_usb_mode_guidance() {
  printf '%s\n' 'Choose ipp_usb only for an IPP-over-USB capable driverless scanner. Choose legacy_usb when the scanner needs a package-provided SANE backend.' >&2
}

collect_usb_identity_from_lsusb() {
  local candidate
  if ! candidate=$(choose_usb_identity "$(remote 'lsusb' 2>&1 || true)"); then
    printf '%s\n' 'No USB identity could be detected automatically. Enter the four-digit vendor and product values after ID from lsusb, for example ID 04a9:1909 becomes 04a9:1909.' >&2
    candidate=$(ask 'USB vendor:product identity from lsusb' '')
  elif [[ "$candidate" == manual ]]; then
    candidate=$(ask 'USB vendor:product identity from lsusb' '')
  fi
  while ! valid_usb_identity "$candidate"; do
    printf '%s\n' 'USB identity must use four hexadecimal vendor and product digits, for example 04a9:1909.' >&2
    candidate=$(ask 'USB vendor:product identity from lsusb' "$candidate")
  done
  printf '%s' "$candidate"
}

printer_connection_confirmation() {
  confirmation_block 'Printer connection' \
    "Queue|$1" "Connection|$2" "URI|$3" "Driver|$4" \
    "USB mode|${5:-not applicable}" "USB ID|${6:-not applicable}"
}
