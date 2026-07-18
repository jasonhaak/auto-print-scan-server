#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/lib/onboarding/server-discovery.sh"

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
