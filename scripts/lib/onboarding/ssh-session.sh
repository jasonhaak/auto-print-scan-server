#!/usr/bin/env bash

ssh_session_cleanup() {
  [[ -n "$ssh_socket" ]] && ssh -o ControlPath="$ssh_socket" -O exit "$admin@$host" >/dev/null 2>&1 || true
  [[ -n "$ssh_socket" ]] && rm -f "$ssh_socket"
  [[ -n "$ssh_socket_dir" ]] && rmdir "$ssh_socket_dir" 2>/dev/null || true
}
remote() { ssh -o ControlPath="$ssh_socket" -o ControlMaster=auto "$admin@$host" "$@"; }
remote_tty() { ssh -tt -o ControlPath="$ssh_socket" -o ControlMaster=auto "$admin@$host" "$@"; }
ssh_session_target_resolves() {
  command -v getent >/dev/null || return 0
  getent ahosts "$host" >/dev/null 2>&1
}
ssh_session_target_resolution() {
  local target=$1 addresses
  printf 'Target entered: %s\n' "$target"
  if [[ "$target" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf 'Address type: IPv4 literal\nResolved IPv4: %s\n' "$target"
    return 0
  fi
  if ! command -v getent >/dev/null; then
    printf 'Name lookup: not checked (getent is unavailable on this computer)\n'
    return 0
  fi
  addresses=$(getent ahostsv4 "$target" 2>/dev/null | awk '{print $1}' | awk '!seen[$0]++')
  [[ -n "$addresses" ]] || { printf 'Name lookup: no IPv4 address found\n'; return 1; }
  printf 'Resolved IPv4:\n%s\n' "$addresses"
}
ssh_session_reachability() {
  local target=$1 address route_output route_ok=true port_ok=true
  address=$(ssh_session_target_resolution "$target" 2>/dev/null | awk '/^Resolved IPv4: / {print $3; exit} /^[0-9]+\./ {print; exit}')
  [[ -n "$address" ]] || { printf 'Route check: skipped because no IPv4 address was resolved\n'; return 1; }
  printf 'Target IPv4: %s\n' "$address"
  if command -v ip >/dev/null; then
    if route_output=$(ip route get "$address" 2>&1); then
      printf 'Route: available\n%s\n' "$route_output"
    else
      printf 'Route: unavailable\n%s\n' "$route_output"
      route_ok=false
    fi
  else
    printf 'Route: not checked (ip is unavailable on this computer)\n'
  fi
  if ssh_port_probe_available; then
    if ssh_port_open "$address"; then
      printf 'TCP port 22: reachable\n'
    else
      printf 'TCP port 22: not reachable within one second\n'
      port_ok=false
    fi
  else
    printf 'TCP port 22: not checked (nc and timeout are unavailable)\n'
  fi
  [[ "$route_ok" == true && "$port_ok" == true ]]
}
ssh_session_open() {
  ssh_session_cleanup
  ssh_socket_dir=$(mktemp -d "${TMPDIR:-/tmp}/raspberry-print-server-ssh.XXXXXX")
  ssh_socket="$ssh_socket_dir/control"
  ssh -o ControlMaster=yes -o ControlPersist=600 -o ControlPath="$ssh_socket" -fN "$admin@$host"
}
