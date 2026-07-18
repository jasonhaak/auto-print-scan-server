#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/server-discovery.sh"
source "$root/scripts/lib/onboarding/ssh-session.sh"

[[ "$(private_ipv4_24 '192.168.178.33')" == '192.168.178.0/24' ]]
[[ "$(private_ipv4_24 '10.23.4.19')" == '10.23.4.0/24' ]]
[[ "$(private_ipv4_24 '172.20.1.3')" == '172.20.1.0/24' ]]
valid_private_ipv4_24_cidr '192.168.178.0/24'
if valid_private_ipv4_24_cidr '192.168.178.1/24'; then
  exit 1
fi
if valid_private_ipv4_24_cidr '192.168.178.0/16'; then
  exit 1
fi
if private_ipv4_24 '8.8.8.8'; then
  exit 1
fi
if private_ipv4_24 '172.32.1.3'; then
  exit 1
fi

valid_private_ipv4_search_cidr '192.168.176.0/22'
valid_private_ipv4_search_cidr '10.23.4.16/28'
if valid_private_ipv4_search_cidr '192.168.176.0/21'; then
  exit 1
fi
if valid_private_ipv4_search_cidr '8.8.8.0/24'; then
  exit 1
fi
if valid_private_ipv4_search_cidr '192.168.178.4/24'; then
  exit 1
fi

addresses=$(private_ipv4_search_addresses '192.168.50.0/30')
[[ "$addresses" == $'192.168.50.1\n192.168.50.2' ]]

resolution=$(ssh_session_target_resolution '192.168.178.33')
[[ "$resolution" == *'Address type: IPv4 literal'* ]]
[[ "$resolution" == *'Resolved IPv4: 192.168.178.33'* ]]
