# raspberry-print-server

[![Release](https://img.shields.io/github/v/release/jasonhaak/raspberry-print-server)](https://github.com/jasonhaak/raspberry-print-server/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/jasonhaak/raspberry-print-server/quality.yml?branch=main&logo=github)](https://github.com/jasonhaak/raspberry-print-server/actions/workflows/quality.yml)
[![Raspberry Pi OS](https://img.shields.io/badge/Raspberry%20Pi%20OS-Debian%20Trixie-C51A4A?logo=raspberrypi)](https://www.raspberrypi.com/software/operating-systems/)

Automated Ansible deployment of one Raspberry Pi as a trusted-LAN print server with CUPS, local DNS-SD discovery, SANE and optional browser scanning through ScanservJS.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
  - [Printer Connections](#printer-connections)
  - [Scanner Settings](#scanner-settings)
  - [Example Configuration](#example-configuration)
- [How it Works](#how-it-works)
- [Installation & Development](#installation--development)
- [Testing](#testing)
- [Author & Licence](#author--licence)

## Features

- **Network printing**: Connects multiple printers by Wi-Fi, Ethernet or USB and shares selected CUPS queues with devices on the home network.
- **Browser scanning**: Makes multiple optional scanners available through one ScanservJS interface, so users select a device and create PDF scans in a browser.
- **Home-network access**: Restricts printing, scanning and optional remote SANE to the configured local IPv4 and IPv6 networks, excluding guest and untrusted devices.
- **Standards before drivers**: Prefers driverless IPP Everywhere and requires an explicit open-source package profile only when an older printer needs one.
- **Repeatable onboarding**: Guides the first setup over SSH, stores non-secret configuration as inventory and can recreate the server after a card or hardware replacement.
- **Automatic scan cleanup**: Deletes completed scans after the selected retention period and warns administrators before scan storage becomes too low.

## Quick Start

You will prepare the administrator machine, prepare a Raspberry Pi with SSH and run onboarding from the trusted LAN.

### 1. Prepare the Administrator Machine

Use Linux, macOS or Windows with WSL2. The administrator machine runs the Bash onboarding script and Ansible over SSH. The Raspberry Pi does not need a desktop, Git checkout or development tooling.

Install or confirm Bash and an OpenSSH client. Linux and macOS provide both by default. On Windows, use an Ubuntu or other Linux WSL2 distribution. Git is recommended for updates and configuration history, but a ZIP download also works.

You can check versions with:

```bash
bash --version
ssh -V
```

The repository can be cloned with:

```bash
git clone https://github.com/jasonhaak/raspberry-print-server.git
cd raspberry-print-server
```

Ansible runs on the administrator machine. This repository installs its pinned Ansible version inside `.venv` so it does not modify the system Python installation. Create that environment and install the required Ansible collections once after cloning:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/ansible-galaxy collection install -r requirements.yml
```

Python is used only on the administrator machine to install and run Ansible. It is not required on the Raspberry Pi for this Quick Start.

### 2. Prepare the Raspberry Pi

Use a **Raspberry Pi 4 Model B with 4 GB RAM** or newer as the recommended baseline for printing plus optional ScanservJS and OCR. Use at least 8 GB storage for printing only and at least 16 GB for scanner-enabled deployments.

Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on a computer with a microSD-card reader. Insert a reliable microSD card, then choose **Raspberry Pi OS Lite (64-bit)** based on Debian Trixie. Do not choose a desktop image, as this repository provisions a headless server.

Before writing the card, open Imager's OS Customization dialog and set:

1. **General**: a hostname, timezone, keyboard layout, bootstrap administrator account and strong password.
2. **Network**: wired Ethernet where possible or, for Wi-Fi, the SSID, password and wireless country.
3. **Remote Access**: enable SSH and choose **Use Password Authentication**.

Clients must share one normal LAN or VLAN with the Raspberry Pi. Printers and scanners may instead
connect directly to an unused Raspberry Pi Ethernet port through a separate private link.

Write the image, safely eject the card, insert it into the Raspberry Pi and power it on.

### 3. Give the Raspberry Pi a Stable Local Address

> **Note**: See Raspberry Pi's [Imager and SSH documentation](https://www.raspberrypi.com/documentation/computers/remote-access.html) for more information.

The Raspberry Pi needs a predictable address so onboarding and future maintenance can reach it after a reboot. For a normal home network, create a **DHCP reservation** in the router:

1. Open the router or modem administration page and find the list of connected devices, DHCP leases or network clients.
2. Locate the Raspberry Pi by its hostname or MAC address. It may appear as `print-server`, `raspberrypi` or the hostname chosen in Imager.
3. Select **Reserve address**, **Static DHCP**, **Address reservation** or the equivalent option.
4. Keep or choose an unused address in the normal LAN range, for example `192.168.178.50`, then save the change.
5. Restart the Raspberry Pi or renew its DHCP lease. Confirm that the router gives it the reserved address.

If the network already has local DNS, create a stable name such as `print-server.home` that resolves to the reserved Raspberry Pi address. `print-server.local` can work through mDNS, but it should not be the only management address because support differs between routers and client devices.

### 4. Run Onboarding

```bash
source .venv/bin/activate
./scripts/onboard
```

Run this command on the administrator machine from the repository directory. The wizard first detects the administrator machine's private `/24` network. You can optionally search it, or enter another routed private `/24` range such as `192.168.178.0/24`, for devices responding on SSH port `22` if the Raspberry Pi address is unknown. The resulting addresses are possible SSH servers, so select one only when you recognise it as the Raspberry Pi. The search does not authenticate or change any device.

The wizard then asks for the Raspberry Pi address and bootstrap administrator, then opens one SSH session that it reuses throughout onboarding. Detected values are labelled clearly. Press Enter to accept a detected value only when it is correct. Activating `.venv` puts its `ansible-playbook` and `ansible-galaxy` commands on the current shell's PATH.

The wizard walks through the following process:

1. **Connect to Raspberry Pi**: optionally searches the current private `/24` network for SSH servers, explains the first SSH host-key confirmation, verifies the bootstrap user once and verifies `sudo` access before changing the Raspberry Pi. SSH and sudo failures stop with recovery guidance.
2. **Read Raspberry Pi Settings**: reports the detected IPv4 network, timezone and locale, then validates trusted IPv4 and optional IPv6 network input.
3. **Discover Devices**: with permission, installs diagnostic tools, searches local DNS-SD and USB devices for up to 15 seconds and reports the number of printer and scanner candidates. It explains how to find an IPP URI or SANE device name when discovery finds nothing. For a compatible USB multifunction device, it temporarily starts `ipp-usb` to discover scanning, then disables it again before configuration continues.
4. **Configure Devices**: asks whether the primary device uses USB, the home network or a direct Ethernet link. Every choice explains what it changes and recommends the normal home-network path when available. A direct link temporarily configures an isolated NetworkManager connection to discover IPP and WSD/eSCL capabilities, then removes it until final confirmation. ScanservJS retention and OCR settings are shared by all scanners.
5. **Review and Commission**: shows a non-secret summary before writing anything. Confirmation then creates timestamped local backups in `.onboard-backups/`, writes production inventory and runs Ansible with normal progress output. It then offers confirmed printer and scanner tests.

SSH and sudo passwords are requested interactively and are never stored in inventory or backups. A later sudo prompt appears only if the Raspberry Pi's sudo timeout expires. If commissioning or a real device test fails, the generated inventory remains available for correction and rerunning.

### 5. Test the Configured Devices

After commissioning, confirm the optional CUPS test page. If a scanner is configured, confirm the optional scanner test PDF and open ScanservJS from a trusted-LAN browser:

```text
http://<pi-hostname-or-address>:8080
```

### 6. Add, Change or Remove Devices

```bash
source .venv/bin/activate
./scripts/onboard
```

Use `scripts/onboard` when adding or changing several devices. It runs discovery, lets you add printers and scanners one at a time, shows the complete result and replaces both device lists only after confirmation. On a rerun, enter every printer and scanner that should remain configured.

## Configuration

The wizard writes inventory-local values in `inventories/production/`. Do not put passwords in inventory.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `trusted_lan_cidrs` | Yes | None | IPv4 and optional IPv6 CIDRs allowed to reach Raspberry Pi-hosted services. |
| `direct_ethernet_links` | No | `[]` | Private Pi-to-device NetworkManager links. These are never trusted client networks. |
| `managed_printers` | Yes | None | List of unique queue names, connections, device URIs and driver modes. |
| `managed_scanners` | No | `[]` | List of SANE device names, connections and backend packages. |
| `scanservjs_retention_days` | With scanner | None | Completed-scan retention period from 1 to 900 days. |
| `scanservjs_ocr_languages` | With scanner | `[eng]` | Selected Tesseract languages, for example `[eng, deu]`. |
| `enable_remote_sane` | No | `false` | Enables SANE-native access for trusted-LAN Linux clients. |

### Printer Connections

| Connection | Use | Notes |
| --- | --- | --- |
| `ipp` or `ipps` | Driverless network printer | Preferred path. |
| `socket` | JetDirect or AppSocket printer | Uses TCP port 9100. |
| `lpd` | Older network printer | Outbound CUPS-to-printer only. The Raspberry Pi does not host LPD. |
| `usb` | Locally connected printer | Requires `ipp_usb` or `legacy_usb`. |

For a legacy printer, use `driver_mode: package_profile`, run assisted discovery and select a profile explicitly. OpenPrinting results are advisory only and never install a driver automatically.

### Device Topologies

Use **network** for a printer or multifunction device connected to the router or switch. This is the
recommended setup because onboarding can discover both IPP printing and WSD/eSCL scanning.

Use **direct Ethernet** only when the device is cabled to an unused Raspberry Pi Ethernet port. The
device needs one static address set on its control panel or web interface. Onboarding recommends a
private `/30` link such as Pi `192.168.50.1/30` and device `192.168.50.2`; it does not expose this
link to trusted-LAN clients or run DHCP for it.

Use USB as a fallback when Ethernet is unavailable. USB commonly supports printing, but scanner support depends on a usable Linux SANE backend for that device. Onboarding detects capabilities; the connection type alone never guarantees scanning.

### Scanner Settings

ScanservJS is the supported cross-platform scanning path. It has no application login, so completed scans are visible to everyone allowed on the trusted LAN until retention deletes them. Remote SANE remains off by default and is intended for compatible native Linux clients.

`scanservjs_ocr_languages` accepts one or more Tesseract language codes. Selecting `[eng, deu]` installs English and German OCR data and configures combined OCR for PDF scans.

### Example Configuration

```yaml
trusted_lan_cidrs:
  - 192.168.178.0/24
direct_ethernet_links: []
managed_printers:
  - name: office-printer
    connection: ipp
    device_uri: ipp://office-printer.local/ipp/print
    driver_mode: driverless
    shared: true
  - name: label-printer
    connection: socket
    device_uri: socket://label-printer.local:9100
    driver_mode: package_profile
    package_profile: brlaser
managed_scanners:
  - device_name: airscan:e0:Office Scanner
    connection: ipp
    backend: sane-airscan
scanservjs_retention_days: 90
scanservjs_ocr_languages: [eng, deu]
enable_remote_sane: false
```

## How it Works

1. `scripts/onboard` runs on the administrator machine. It creates production inventory and invokes Ansible over SSH on the Raspberry Pi.
2. Baseline roles validate the supported platform, configure users and SSH, then apply the trusted-LAN firewall policy.
3. CUPS creates or updates every managed queue and removes only queues recorded as previously Ansible-managed. Avahi provides link-local DNS-SD discovery when a queue is shared. CUPS administration remains localhost-only.
4. The scanner path installs SANE and the checksum-pinned ScanservJS package. ScanservJS output is retained for the selected period, while free-space checks write to the journal and show an SSH-login warning.
5. A run with `print_server_commissioning=true` requires every declared device to be reachable. Routine maintenance warns about unavailable hardware and preserves existing queues.

## Installation & Development

1. **Clone the repository**

   ```bash
   git clone https://github.com/jasonhaak/raspberry-print-server.git
   cd raspberry-print-server
   ```

2. **Install dependencies**

   ```bash
   python3 -m venv .venv
   .venv/bin/pip install -r requirements-dev.txt
   .venv/bin/ansible-galaxy collection install -r requirements.yml
   ```

3. **Configure production inventory**

   ```bash
   scripts/onboard
   ```

4. **Run a maintenance pass**

   ```bash
   .venv/bin/ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml
   ```

## Testing

This repository uses `yamllint`, `ansible-lint`, Bash syntax checking and Ansible playbook syntax checks.

```bash
bash -n scripts/onboard
bash test/onboarding_prompts_test.sh
bash test/onboarding_server_discovery_test.sh
yamllint .
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/print-server.yml --syntax-check
ansible-playbook playbooks/scanner.yml --syntax-check
ansible-playbook playbooks/discover-printer.yml --syntax-check
```

The static suite checks configuration syntax and Ansible conventions. Follow [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for required Raspberry Pi, printer, scanner, mDNS and firewall acceptance checks.

## Author & Licence

This code was written by Jason Haak and is licensed under the MIT licence.
