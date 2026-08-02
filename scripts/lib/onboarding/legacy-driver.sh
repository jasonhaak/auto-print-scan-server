#!/usr/bin/env bash

declare -A LEGACY_PROFILE_MODELS=()

prepare_and_choose_cups_model() {
  local profile=$1 uri=$2 evidence=${3:-} prefix models preparation_output recovery
  while true; do
    prefix=$(package_profile_model_prefix "$profile") || return 1
    if [[ -z "${LEGACY_PROFILE_MODELS[$profile]:-}" ]]; then
      subsection 'Prepare Legacy Printer Driver'
      printf 'Profile %s installs its generic Debian driver package, starts CUPS, then reads its advertised models. It does not write production inventory or create a print queue.\n' "$profile" >&2
      yes_default "Install this driver package and inspect its CUPS models?" || return 1
      local -a arguments=(-i "$legacy_driver_inventory" "$root/playbooks/prepare-printer-profile.yml" -e "{\"selected_package_profiles\":[\"$profile\"]}")
      if ! remote 'sudo -n true' >/dev/null 2>&1; then
        printf '%s\n' 'Ansible needs the Raspberry Pi sudo password to prepare this driver package.' >&2
        arguments+=(--ask-become-pass)
      fi
      step_stream preparation_output 'Prepare legacy driver package' 'ansible-playbook playbooks/prepare-printer-profile.yml' \
        env ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPath=$ssh_socket" ansible-playbook "${arguments[@]}" || return 1
      step_check models 'Read CUPS models from the Raspberry Pi' 'lpinfo -m' remote 'lpinfo -m' || return 1
      LEGACY_PROFILE_MODELS[$profile]=$models
    else
      printf 'Reusing the CUPS model list already prepared for package profile %s.\n' "$profile" >&2
    fi
    if LEGACY_SELECTED_CUPS_MODEL=$(choose_cups_model "$profile" "$uri" "${LEGACY_PROFILE_MODELS[$profile]}" "$prefix" "$evidence"); then
      LEGACY_SELECTED_PACKAGE_PROFILE=$profile
      return 0
    fi
    recovery=$(recovery_choice 'Legacy model recovery (retry, profile, stop)' retry retry profile stop) || return 1
    case "$recovery" in
      retry) unset 'LEGACY_PROFILE_MODELS[$profile]' ;;
      profile) profile=$(choose_package_profile "$profile") ;;
      stop) return 1 ;;
    esac
  done
}
