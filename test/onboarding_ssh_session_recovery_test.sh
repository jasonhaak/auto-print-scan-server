#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/ssh-session.sh"

# ssh_session_open/cleanup shell out to the real ssh binary to manage a ControlMaster socket.
# Stub it so this test exercises the socket bookkeeping (mktemp path, cleanup) without an SSH
# server: ssh_session_open backgrounds `ssh -fN`, ssh_session_cleanup runs `ssh -O exit`.
ssh() { return 0; }

admin=testuser
host=testhost
ssh_socket=''
ssh_socket_dir=''

ssh_session_open
first_socket=$ssh_socket
first_dir=$ssh_socket_dir
[[ -n "$first_socket" ]]
[[ -d "$first_dir" ]]

# Simulate an interrupted control socket between attempts (e.g. the Pi rebooted or dropped the
# connection mid-step): remove the socket directory out from under the session, as a dead
# ControlMaster would leave behind.
rm -rf "$first_dir"

# A retry must explicitly recreate the session rather than relying on ControlMaster=auto to
# paper over the dead socket: ssh_session_cleanup then ssh_session_open should produce a fresh
# socket path distinct from the interrupted one.
ssh_session_cleanup
ssh_session_open
second_socket=$ssh_socket
second_dir=$ssh_socket_dir

[[ -n "$second_socket" ]]
[[ "$second_socket" != "$first_socket" ]]
[[ ! -e "$first_dir" ]]
[[ -d "$second_dir" ]]

ssh_session_cleanup
[[ ! -e "$second_dir" ]]

# A plain non-interactive SSH command execution does not always inherit /usr/sbin or /sbin (where
# lpinfo, sane-find-scanner and similar admin tools live), even though a login shell for the same
# account would. remote()/remote_tty() must prefix every remote command with an explicit PATH so
# tool lookups do not silently fail with "command not found" depending on the Pi's SSH/PAM setup.
captured_command=''
ssh() {
  for argument in "$@"; do
    captured_command=$argument
  done
}
remote 'lpinfo -v'
[[ "$captured_command" == *'export PATH='* ]]
[[ "$captured_command" == *'/usr/sbin'* ]]
[[ "$captured_command" == *'lpinfo -v'* ]]

captured_command=''
remote_tty 'sudo -v'
[[ "$captured_command" == *'export PATH='* ]]
[[ "$captured_command" == *'/usr/sbin'* ]]
[[ "$captured_command" == *'sudo -v'* ]]
