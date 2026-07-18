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

valid_private_ipv4_search_cidr() {
  local cidr=$1 checker=${ONBOARD_PYTHON:-python3}
  "$checker" -c '
import ipaddress
import sys

try:
    network = ipaddress.ip_network(sys.argv[1], strict=True)
except ValueError:
    raise SystemExit(1)

private_blocks = tuple(ipaddress.ip_network(item) for item in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
valid = network.version == 4 and network.num_addresses <= 1024 and any(network.subnet_of(block) for block in private_blocks)
raise SystemExit(0 if valid else 1)
' "$cidr" >/dev/null 2>&1
}

private_ipv4_search_addresses() {
  local cidr=$1 checker=${ONBOARD_PYTHON:-python3}
  valid_private_ipv4_search_cidr "$cidr" || return 1
  "$checker" -c '
import ipaddress
import sys

for address in ipaddress.ip_network(sys.argv[1], strict=True).hosts():
    print(address)
' "$cidr"
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
  local cidr=$1 address pid
  local -a pids=()
  valid_private_ipv4_search_cidr "$cidr" || return 1
  ssh_port_probe_available || return 2
  while IFS= read -r address; do
    (ssh_port_open "$address" && printf '%s\n' "$address") &
    pids+=("$!")
    if (( ${#pids[@]} == 16 )); then
      for pid in "${pids[@]}"; do wait "$pid" || true; done
      pids=()
    fi
  done < <(private_ipv4_search_addresses "$cidr")
  for pid in "${pids[@]}"; do wait "$pid" || true; done
}
