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
- [Troubleshooting and Experimental Hardware](#troubleshooting-and-experimental-hardware)
- [Author & Licence](#author--licence)

## Features

- **Network printing**: Connects multiple printers by Wi-Fi, Ethernet or USB and shares selected CUPS queues with devices on the home network.
- **Browser scanning**: Makes multiple optional scanners available through one ScanservJS interface, so users select a device and create PDF scans in a browser.
- **Home-network access**: Restricts printing, scanning and optional remote SANE to the configured local IPv4 and IPv6 networks, excluding guest and untrusted devices.
- **Standards before drivers**: Prefers driverless IPP Everywhere and requires an explicit open-source package profile only when an older printer needs one.
- **Assisted lifecycle**: Guides first setup, discovers device settings and provides focused add, edit and delete commands for later changes.
- **Automatic scan cleanup**: Deletes completed scans after the selected retention period and warns administrators before scan storage becomes too low.

## Quick Start

You will prepare the administrator machine, prepare a Raspberry Pi with SSH and run onboarding from the trusted LAN.

### 1. Prepare the Administrator Machine

Use Linux, macOS or Windows with WSL2. The administrator machine runs the Bash onboarding script and Ansible over SSH. The Raspberry Pi does not need a desktop, Git checkout or development tooling.

Install or confirm Bash, OpenSSH and Python 3.12 or newer. Linux and macOS provide Bash and SSH by default. On Windows, use an Ubuntu or other Linux WSL2 distribution. Git is recommended for updates and configuration history, but a ZIP download also works.

You can check versions with:

```bash
bash --version
ssh -V
python3 --version
```

The repository can be cloned with:

```bash
git clone https://github.com/jasonhaak/raspberry-print-server.git
cd raspberry-print-server
```

Ansible runs on the administrator machine. The setup command creates `.venv` and installs the pinned tools as well as Ansible collections without modifying the system Python installation:

```bash
./scripts/setup
```

Running `./scripts/onboard` performs this setup automatically when Ansible is not ready. Python is used only on the administrator machine. It is not required on the Raspberry Pi.

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
./scripts/onboard
```

Run this command on the administrator machine from the repository directory. The wizard detects the local private network, then explicitly offers to search it, search another RFC1918 network or skip the search. A search range may contain at most 1,024 addresses. The resulting addresses are possible SSH servers, so select one only when you recognise it as the Raspberry Pi. The search does not authenticate or change any device.

The wizard asks for the Raspberry Pi address and bootstrap administrator, then opens one SSH session that it reuses for discovery and Ansible. Detected values are labelled clearly. Press Enter to accept a value only when it matches the intended server or device.

The wizard walks through the following process:

1. **Connect to Raspberry Pi**: searches the detected or manually entered private network for SSH servers when requested, explains the first SSH host-key confirmation, verifies the bootstrap user once and verifies `sudo` access before changing the Raspberry Pi. SSH and sudo failures offer retry, a corrected address or user, or stop in place, without repeating earlier steps.
2. **Read Raspberry Pi Settings**: reports the connected IPv4 route with its actual prefix, timezone and locale, then validates trusted IPv4 and optional IPv6 input.
3. **Discover Devices**: asks whether to search all connections, LAN only, USB only or skip discovery. With permission, it installs diagnostic tools and checks standard CUPS, DNS-SD, ipp-usb and SANE evidence. Advertised scanners are shown as hints, but only exact SANE identifiers can be selected. A failed install or an empty result offers retry, a changed search scope, manual entry or stop.
4. **Configure Devices**: prominently asks how the device is connected and always permits LAN, direct Ethernet or USB. A direct link temporarily configures an isolated NetworkManager connection and checks IPP, CUPS SNMP, ports 9100 and 515 plus SANE before removing the link; a discovered scanner is only recommended when its identifier or hostname resolution is bound to that exact direct device address, never to an unrelated LAN scanner. A failed link, interface or ping offers retry, corrected settings, manual entry or stop. ScanservJS retention, OCR and port settings are shared by all scanners.
5. **Review and Commission**: shows a non-secret summary before writing production inventory or provisioning services. Confirmation then creates timestamped local backups in `.onboard-backups/`, writes production inventory and runs Ansible with normal progress output. A failed collection install or commissioning run offers retry, switching to `scripts/manage-devices` or stop, with the committed inventory and backup left untouched either way. It then offers confirmed printer and scanner tests: the printer test tracks the actual CUPS job and polls for a bounded, reported outcome without claiming paper output; the scanner test requires non-empty output and checks that ScanservJS has a real local listener, not only that its service is enabled.

SSH and sudo passwords are requested interactively and are never stored in inventory or backups. When a standard local SSH public key exists, onboarding installs it for the managed administrator so later maintenance can connect without the account password. If commissioning or a real device test fails, the generated inventory remains available for correction and rerunning.

Searches and remote operations show a label and a result tag as they run; a successful read-only check collapses to that single line, while a failed check or any state-changing action always shows its full command and output. The complete sanitized transcript is retained with mode `0600` under `.onboard-logs/` regardless of what the terminal shows. Run `./scripts/onboard --verbose` to show every check's full output, not only failures and actions.

### 5. Test the Configured Devices

After commissioning, confirm the optional CUPS test page. If a scanner is configured, confirm the optional scanner test PDF and open ScanservJS from a trusted-LAN browser, using the configured `scanservjs_port` (8080 by default):

```text
http://<pi-hostname-or-address>:8080
```

### 6. Add, Change or Remove Devices

```bash
./scripts/manage-devices
./scripts/manage-devices list
./scripts/manage-devices add printer
./scripts/manage-devices add scanner
./scripts/manage-devices add link
./scripts/manage-devices edit printer office-printer
./scripts/manage-devices edit link eth1
./scripts/manage-devices delete scanner 'airscan:e0:Office Scanner'
./scripts/manage-devices delete link eth1
./scripts/manage-devices apply
```

Running the command with no arguments shows current definitions and prompts for an action interactively; every other form runs that action directly. `add` offers scoped assisted discovery (printer-only or scanner-only, matching the device being added) before manual entry. `edit` keeps every current value as its prompt default. `delete` shows the exact definition and requires confirmation. Printer, scanner and direct Ethernet link changes create timestamped backups and replace only the selected definition. Links remain independent because one multifunction device can use the same link for printing and scanning; deleting a device never deletes its link. Deleting the only printer is rejected because the repository provisions a print server. Deleting the last scanner disables scanner services and timers while preserving completed scans.

Running `./scripts/onboard` after first setup offers this device workflow. Use `./scripts/onboard --reconfigure` only when server-level settings such as the target host, trusted LAN or direct Ethernet links must be rebuilt.

## Configuration

The wizard writes inventory-local values in `inventories/production/`. Do not put passwords in inventory.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `common_supported_debian_major_versions` | No | `['13']` | Tested Raspberry Pi OS Debian bases. Add a release only after repository QA and hardware acceptance. |
| `common_supported_architectures` | No | `[aarch64]` | Tested target architectures. This is model-independent; supported 64-bit Raspberry Pi boards report `aarch64`. |
| `trusted_lan_cidrs` | Yes | None | IPv4 and optional IPv6 CIDRs allowed to reach Raspberry Pi-hosted services. |
| `direct_ethernet_links` | No | `[]` | Private Pi-to-device NetworkManager links. These are never trusted client networks. |
| `managed_printers` | Yes | None | List of unique queue names, connections, device URIs and driver modes. |
| `managed_scanners` | No | `[]` | List of SANE device names, connections and backend packages. |
| `scanservjs_retention_days` | With scanner | None | Completed-scan retention period from 1 to 900 days. |
| `scanservjs_ocr_languages` | With scanner | `[eng]` | Selected Tesseract languages, for example `[eng, deu]`. |
| `scanservjs_port` | With scanner | `8080` | Local TCP port ScanservJS listens on, from 1 to 65535. |
| `enable_remote_sane` | No | `false` | Enables SANE-native access for trusted-LAN Linux clients. |
| `enable_unattended_upgrades` | No | `false` | Enables unattended security updates without automatic reboot. |

### Printer Connections

| Connection | Use | Notes |
| --- | --- | --- |
| `ipp` or `ipps` | Driverless network printer | Preferred path. |
| `socket` | JetDirect or AppSocket printer | Uses TCP port 9100 and normally needs a package profile. |
| `lpd` | Older network printer | Requires the exact remote queue and normally a package profile. The Raspberry Pi does not host LPD. |
| `usb` | Locally connected printer | Requires `ipp_usb` or `legacy_usb`. |

For a legacy printer, use `driver_mode: package_profile`. Onboarding first prepares the selected generic driver package, then lists the exact CUPS models advertised by that Raspberry Pi and requires an explicit choice. The queue stores both `package_profile` and `cups_model`; a future printer model therefore does not require a repository change. When the URI is `ipp://` or `ipps://`, onboarding may recommend a package profile from identity evidence, but never selects it automatically.

### Device Topologies

Use **network** for a printer or multifunction device connected to the router or switch. This is the
recommended setup because onboarding can discover both IPP printing and WSD/eSCL scanning.

Use **direct Ethernet** only when the device is cabled to an unused Raspberry Pi Ethernet port. The
device needs one static address set on its control panel or web interface. Onboarding recommends a
private `/30` link such as Pi `192.168.50.1/30` and device `192.168.50.2`; it does not expose this
link to trusted-LAN clients or run DHCP for it. Initial onboarding creates one link inline. Later
links can be added, edited or deleted through `scripts/manage-devices`. A direct-link `/30` must
not overlap any trusted-LAN CIDR.

Use USB as a fallback when Ethernet is unavailable. USB commonly supports printing, but scanner support depends on a usable Linux SANE backend for that device. Onboarding accepts only an exact CUPS `usb://` endpoint or a new ipp-usb endpoint as printer evidence. It accepts exact standard SANE identifiers as scanner evidence. When `scanimage -L` reports a recognised preinstalled device backend such as `brother:bus…` or `brother:net…`, onboarding can retain that exact identifier without installing or changing the backend package.

The playbooks do not check for one concrete Raspberry Pi model. They check Raspberry Pi OS, a tested Debian base and architecture through the compatibility variables above. This keeps future releases easy to add while preventing an untested operating-system upgrade from changing packages and services unexpectedly.

### Scanner Settings

ScanservJS is the supported cross-platform scanning path. It has no application login, so completed scans are visible to everyone allowed on the trusted LAN until retention deletes them. Remote SANE remains off by default and is intended for compatible native Linux clients.

Scanner connection `network` represents an exact SANE identifier reached over IP, including `net:` identifiers from package-provided backends. Existing `ipp` and `ipps` values remain accepted. Connection `usb` requires an explicit `ipp_usb` or `legacy_usb` mode.

Set `backend_install: false` for a scanner backend installed and maintained outside this repository. The deployment still installs `sane-utils` and uses the configured identifier for validation, but does not install, update or register that backend. Use this only after `scanimage -L` has reported the exact device and a real test scan has succeeded.

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
    cups_model: drv:///brlaser.drv/br7360.ppd
managed_scanners:
  - device_name: airscan:e0:Office Scanner
    connection: ipp
    backend: sane-airscan
scanservjs_retention_days: 90
scanservjs_ocr_languages: [eng, deu]
scanservjs_port: 8080
enable_remote_sane: false
```

## How it Works

1. `scripts/onboard` runs on the administrator machine. It creates production inventory and invokes Ansible over SSH on the Raspberry Pi.
2. Baseline roles validate the supported platform, configure users and SSH, then apply the trusted-LAN firewall policy.
3. CUPS creates or updates every managed queue and removes only queues recorded as previously Ansible-managed. Avahi provides link-local DNS-SD discovery when a queue is shared. CUPS administration remains localhost-only.
4. The scanner path installs SANE and the checksum-pinned ScanservJS package. Removing the last scanner stops browser scanning, remote SANE and scanner timers without deleting completed scans.
5. A run with `print_server_commissioning=true` requires every declared device to be reachable, using the exact probe tool and, for a declared scanner, its configured SANE backend; commissioning fails distinctly when a probe tool itself is missing rather than reporting it as an unreachable device, and it does not depend on interactive discovery having run first. Routine maintenance warns about unavailable hardware and preserves existing queues.
6. UFW, CUPS queues and direct Ethernet links keep project-owned state files. Later runs remove stale project entries without resetting unrelated administrator configuration.

## Installation & Development

1. **Clone the repository**

   ```bash
   git clone https://github.com/jasonhaak/raspberry-print-server.git
   cd raspberry-print-server
   ```

2. **Install dependencies**

   ```bash
   ./scripts/setup
   ```

3. **Configure production inventory**

   ```bash
   scripts/onboard
   ```

4. **Run a maintenance pass**

   ```bash
   ./scripts/manage-devices apply
   ```

## Testing

Run the same shell tests, inventory tests, YAML lint, Ansible lint and playbook syntax checks used by CI:

```bash
./scripts/qa
```

The static suite checks configuration syntax and Ansible conventions. Follow [acceptance testing](docs/acceptance-testing.md) for required Raspberry Pi, printer, scanner, mDNS and firewall acceptance checks.

## Troubleshooting and Experimental Hardware

- [Brother scanners with brscan2](docs/guides/brother-scanners.md): manual fallback when a Brother scanner is available but standard SANE backends cannot perform a scan.

## Author & Licence

This code was written by Jason Haak and is licensed under the MIT licence.
