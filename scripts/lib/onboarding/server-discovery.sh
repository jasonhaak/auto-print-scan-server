#!/usr/bin/env bash

private_ipv4_24() {
  local address=$1 first second third fourth
  IFS=. read -r first second third fourth <<<"$address"
  [[ "$first" =~ ^[0-9]+$ && "$second" =~ ^[0-9]+$ && "$third" =~ ^[0-9]+$ && "$fourth" =~ ^[0-9]+$ ]] || return 1
  (( first <= 255 && second <= 255 && third <= 255 && fourth <= 255 )) || return 1
  (( first == 10 || (first == 172 && second >= 16 && second <= 31) || (first == 192 && second == 168) )) || return 1
  printf '%s.%s.%s.0/24' "$first" "$second" "$third"
}

valid_private_ipv4_24_cidr() {
  local cidr=$1 address
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}0/24$ ]] || return 1
  address=${cidr%/24}
  [[ "$(private_ipv4_24 "$address")" == "$cidr" ]]
}

administrator_lan_cidr() {
  local address interface
  if command -v ip >/dev/null; then
    address=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')
  elif command -v route >/dev/null && command -v ipconfig >/dev/null; then
    interface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
    [[ -n "$interface" ]] && address=$(ipconfig getifaddr "$interface" 2>/dev/null || true)
  fi
  [[ -n "${address:-}" ]] && private_ipv4_24 "$address"
}

ssh_port_probe_available() {
  command -v nc >/dev/null || command -v timeout >/dev/null
}

ssh_port_open() {
  local address=$1
  if command -v nc >/dev/null; then
    nc -z -w 1 "$address" 22 >/dev/null 2>&1
  elif command -v timeout >/dev/null; then
    timeout 1 bash -c 'exec 3<>"/dev/tcp/$1/22"' _ "$address" >/dev/null 2>&1
  else
    return 2
  fi
}

find_ssh_hosts() {
  local cidr=$1 base number address pid
  local -a pids=()
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}0/24$ ]] || return 1
  ssh_port_probe_available || return 2
  base=${cidr%0/24}
  for number in {1..254}; do
    address="${base}${number}"
    (ssh_port_open "$address" && printf '%s\n' "$address") &
    pids+=("$!")
    if (( ${#pids[@]} == 16 )); then
      for pid in "${pids[@]}"; do wait "$pid" || true; done
      pids=()
    fi
  done
  for pid in "${pids[@]}"; do wait "$pid" || true; done
}
