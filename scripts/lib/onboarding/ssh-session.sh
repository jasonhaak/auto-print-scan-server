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
ssh_session_open() {
  ssh_socket_dir=$(mktemp -d "${TMPDIR:-/tmp}/raspberry-print-server-ssh.XXXXXX")
  ssh_socket="$ssh_socket_dir/control"
  ssh -o ControlMaster=yes -o ControlPersist=600 -o ControlPath="$ssh_socket" -fN "$admin@$host"
}
