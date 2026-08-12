#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/ssh-session.sh"
source "$root/scripts/lib/onboarding/device-discovery.sh"

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

# A bare SSH command's restricted PATH omits the directory containing lpinfo. Run the remote
# command against a test-only administration directory to prove the prefix restores lookup,
# then verify its output creates a legacy_usb candidate.
restricted_remote_path=/usr/bin:/bin
[[ "$restricted_remote_path" != *'/usr/sbin'* ]]
test_admin_path=$(mktemp -d "${TMPDIR:-/tmp}/raspberry-print-server-lpinfo.XXXXXX")
printf '%s\n' '#!/usr/bin/env bash' 'printf "direct usb://Brother/MFC-7360N?serial=123\\n"' >"$test_admin_path/lpinfo"
chmod +x "$test_admin_path/lpinfo"
remote_path_prefix="export PATH=\"$test_admin_path:$restricted_remote_path\";"
ssh() {
  local argument remote_command=''
  for argument in "$@"; do remote_command=$argument; done
  env PATH="$restricted_remote_path" bash -c "$remote_command"
}
lpinfo_output=$(remote 'lpinfo -v')
legacy_candidate=$(cups_printer_candidates "$lpinfo_output")
[[ "$legacy_candidate" == 'USB printer (usb://Brother/MFC-7360N?serial=123)|usb|usb://Brother/MFC-7360N?serial=123|legacy_usb' ]]
rm -rf "$test_admin_path"
remote_path_prefix='export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH";'

captured_command=''
ssh() {
  for argument in "$@"; do
    captured_command=$argument
  done
}
remote_tty 'sudo -v'
[[ "$captured_command" == *'export PATH='* ]]
[[ "$captured_command" == *'/usr/sbin'* ]]
[[ "$captured_command" == *'sudo -v'* ]]

# Finding 13: OpenSSH prints "Shared connection to HOST closed." to stderr when a -tt
# (pty-allocating) session over a ControlMaster connection tears down. This noise was leaking
# into every remote_tty step's captured technical output (reproduced live: it appeared as the
# Output of both "Start CUPS for endpoint discovery" and "Stop IPP-over-USB for direct endpoint
# discovery"). -q suppresses OpenSSH's own diagnostic/warning chatter without touching the
# remote command's real output.
captured_arguments=()
ssh() { captured_arguments=("$@"); }
remote_tty 'sudo -v'
found_quiet_flag=false
for argument in "${captured_arguments[@]}"; do
  [[ "$argument" == '-q' ]] && found_quiet_flag=true
done
[[ "$found_quiet_flag" == true ]]
