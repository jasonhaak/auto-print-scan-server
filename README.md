# auto-print-scan-server

[![Release](https://img.shields.io/github/v/release/jasonhaak/auto-print-scan-server)](https://github.com/jasonhaak/auto-print-scan-server/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/jasonhaak/auto-print-scan-server/ci.yml?branch=main&logo=github)](https://github.com/jasonhaak/auto-print-scan-server/actions/workflows/ci.yml)
[![Debian Trixie](https://img.shields.io/badge/Debian-Trixie-A81D33?logo=debian)](https://www.debian.org/releases/trixie/)

This project turns a Debian host into a print and scan server for one trusted LAN. It manages CUPS queues, optional ScanservJS browser scanning and selected SANE access from an administrator machine over SSH. Guided onboarding collects the network and device settings, shows the resulting configuration and then commissions the server.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [How it Works](#how-it-works)
- [Installation & Development](#installation--development)
- [Testing](#testing)
- [Author & Licence](#author--licence)

## Features

- **Guided onboarding**: Collects server and device settings, discovers usable devices where possible and commissions the resulting configuration after review.
- **Scoped administration**: Adds, edits or removes one device definition without repeating first-time server setup.
- **Managed CUPS queues**: Creates and updates declared printer queues for IPP, IPPS, Socket, LPD and USB connections.
- **Browser scanning**: Exposes managed scanners through ScanservJS with PDF output, OCR, retention and low-storage warnings.
- **Trusted-LAN access**: Limits SSH, printing, browser scanning and optional remote SANE to configured IPv4 and IPv6 CIDRs.
- **Driver selection**: Uses driverless standards first, then explicit Debian package profiles for supported legacy printers.
- **Direct device links**: Supports an isolated Ethernet link between the server and a printer or multifunction device.

## Quick Start

The administrator machine runs Bash, Python and Ansible. The server only needs Debian, SSH access and a bootstrap administrator with `sudo`.

### 1. Prepare the Administrator Machine

Use Linux, macOS or Windows with WSL2. The administrator machine needs:

- Bash to run the project scripts.
- OpenSSH to connect to the server.
- Python 3.12 or later to run Ansible locally.
- Git to clone and update the repository. A ZIP download also works, but does not provide update history.

```bash
git clone https://github.com/jasonhaak/auto-print-scan-server.git
cd auto-print-scan-server
```

### 2. Install the Administrator Tools

Ansible runs from the administrator machine, not from the server. Run the setup command once for each administrator machine to create the repository-local Python environment and install the pinned Ansible tools and collections.

```bash
./scripts/setup
```

`./scripts/setup` creates `.venv` in the repository and does not modify the system Python installation.

### 3. Prepare the Server

The server must meet these requirements:

- Debian 13 on `aarch64` or `x86_64`, or Raspberry Pi OS Lite 32-bit based on Debian Trixie on `armv6l`. This includes the Raspberry Pi Zero W, current 64-bit Raspberry Pi systems and conventional Intel or AMD computers.
- SSH reachable from the administrator machine, using password or key authentication.
- A bootstrap administrator account with `sudo` access.
- One Ethernet or Wi-Fi connection on the trusted LAN; an additional unused Ethernet interface is optional for a direct device link.

Install Debian 13 with the installer or image supplied for the hardware. During installation, choose a hostname, create the bootstrap administrator, connect the server to the trusted LAN and enable SSH.

#### DHCP Reservation

Whichever method you use, once the device is running you still need a stable, predictable address for it, since onboarding and later maintenance both need to find the same server again after a reboot. For a normal home network, create a **DHCP reservation** in the router:

1. Open the router or modem administration page and find the list of connected devices, DHCP leases or network clients.
2. Locate the server by its hostname or MAC address.
3. Select **Reserve address**, **Static DHCP**, **Address reservation** or the equivalent option.
4. Keep or choose an unused address in the normal LAN range, for example `192.168.178.50`, then save the change.
5. Restart the server or renew its DHCP lease. Confirm that the router gives it the reserved address.

If the network already has local DNS, create a stable name such as `print-scan-server.home` that resolves to the reserved server address. `print-scan-server.local` can work through mDNS, but it should not be the only management address because support differs between routers and client devices.

#### Raspberry Pi Example

> NOTE: This is the concrete path actually built and tested for this repository.

Use a **Raspberry Pi 4 Model B with 4 GB RAM** or newer as the recommended baseline for printing plus optional ScanservJS and OCR. Use at least 8 GB storage for printing only and at least 16 GB for scanner-enabled deployments.

A **Raspberry Pi Zero W** is also supported with **Raspberry Pi OS Lite (32-bit)**. Its 512 MB RAM and single CPU core make the Pi 4 baseline the better choice for ScanservJS, OCR or frequent large scans.

Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on a computer with a microSD-card reader. Insert a reliable microSD card, then choose **Raspberry Pi OS Lite (64-bit)** based on Debian Trixie for a 64-bit Pi, or **Raspberry Pi OS Lite (32-bit)** for a Raspberry Pi Zero W. Do not choose a desktop image, as this repository provisions a headless server.

Before writing the card, open Imager's OS Customization dialog and set:

1. **General**: a hostname, timezone, keyboard layout, bootstrap administrator account and strong password.
2. **Network**: wired Ethernet where possible or, for Wi-Fi, the SSID, password and wireless country.
3. **Remote Access**: enable SSH and choose **Use Password Authentication**.

Clients must share one normal LAN or VLAN with the server. Printers and scanners may instead connect directly to an unused server Ethernet port through a separate private link.

Write the image, safely eject the card, insert it into the server and power it on. It may appear in the router's DHCP client list as `print-server`, `raspberrypi` or the hostname chosen above.

See Raspberry Pi's [Imager and SSH documentation](https://www.raspberrypi.com/documentation/computers/remote-access.html) for more detail on this path.

### 4. Give Network Devices Stable Addresses

> **Note:** This step applies only to printers and scanners connected over a network. USB devices do not need a network address.

Network printers and scanners need addresses that remain stable after a restart. The appropriate method depends on how the device connects:

| Connection | What to configure before onboarding |
| --- | --- |
| Router or switch | Create a DHCP reservation for the printer or scanner in the router, using its MAC address. This lets the device keep one LAN address without configuring an address on the device itself. |
| Direct Ethernet link | Configure a static private IPv4 address on the device through its control panel or web interface. A typical link uses server `192.168.50.1/30` and device `192.168.50.2`. The addresses must not overlap the trusted LAN. |
| USB | No network address is needed. |

Onboarding configures the server side of a direct Ethernet link after you enter its details. It cannot configure the device's own static address.

### 5. Run Onboarding

```bash
./scripts/onboard
```

The wizard opens a reusable SSH session for the onboarding, confirms the trusted LAN, discovers printers and scanners, collects device definitions, writes production inventory and commissions the server. It requests SSH and `sudo` passwords interactively and never stores them in inventory or backups.

Before it writes inventory or changes the server, onboarding shows a non-secret summary. It creates local timestamped backups in `.onboard-backups/` and retains full sanitised transcripts in `.onboard-logs/`. Use `./scripts/onboard --verbose` to show every check's technical output.

### 6. Use the Services

After commissioning, print from clients on the trusted LAN. Shared queues are advertised through DNS-SD. If a scanner is configured, open ScanservJS in a trusted-LAN browser:

```text
http://<server-hostname-or-address>:8080
```

`8080` is the default; use the configured `scanservjs_port` if it differs. ScanservJS has no application login, so completed scans are visible to everyone on the trusted LAN until the retention timer removes them.

### 7. Manage Devices After Onboarding

Use `scripts/manage-devices` for a printer, scanner or direct-link change. It backs up the production inventory before each add, edit or delete and only changes the selected definition.

Use it after initial commissioning when the server itself is unchanged. It is the narrower path for replacing a printer, adding a scanner or correcting one device endpoint. The script saves each inventory change first, then offers to apply it to the server.

| Command | Use |
| --- | --- |
| `./scripts/manage-devices --help` | Show the available commands and the identity each command expects. |
| `./scripts/manage-devices` | List the current definitions and open an interactive menu. |
| `./scripts/manage-devices list` | Report the managed printers, scanners and direct Ethernet links without changing them. |
| `./scripts/manage-devices add printer` | Discover and add a printer. Use `add scanner` or `add link` for the other definition types. |
| `./scripts/manage-devices edit printer office-printer` | Edit one definition by its queue name, exact SANE device name or server Ethernet interface. Existing values are prompt defaults, so Enter keeps them. |
| `./scripts/manage-devices delete scanner 'airscan:e0:Office Scanner'` | Show one definition and request confirmation before removing it. Deleting a printer or scanner does not remove an independent direct Ethernet link. |
| `./scripts/manage-devices apply` | Provision the current inventory without changing a definition. |

### Command Overview

`./start` is the repository entry point. Run it with no arguments to open an interactive menu or use `./start help` for the complete command reference.

| Command | Use |
| --- | --- |
| `./start` | Open the interactive menu and choose the appropriate workflow. |
| `./start setup` | Prepare the administrator machine with the local Python environment and Ansible dependencies. |
| `./start onboard` | Run first-time guided server setup and commissioning. |
| `./start reconfigure` | Rebuild server-level settings and revisit every device definition. |
| `./start manage-devices` | Add, edit, delete or apply a scoped device change. |
| `./start qa` | Run the repository validation suite. |
| `./start help` | Show this command reference and usage guidance. |

## Configuration

Onboarding writes non-secret production values to `inventories/production/`. Do not store passwords in inventory.

### Variable Descriptions

These variables are the declared state of the server. Onboarding writes them to production inventory and later Ansible runs compare that inventory with the server before creating, updating or removing only project-managed resources.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `common_supported_debian_major_versions` | No | `['13']` | Debian major versions accepted by the platform validation. Add one only after repository QA and hardware acceptance. |
| `common_supported_architectures` | No | `[aarch64, x86_64, armv6l]` | Target architectures accepted by the platform validation. `armv6l` covers Raspberry Pi OS Lite 32-bit on the Raspberry Pi Zero W. |
| `trusted_lan_cidrs` | Yes | None | IPv4 and optional IPv6 CIDRs allowed to reach server-hosted services. |
| `direct_ethernet_links` | No | `[]` | Private NetworkManager links between the server and devices; never trusted client networks. |
| `managed_printers` | Yes | None | Printer queue names, endpoints, driver modes and sharing settings. |
| `managed_scanners` | No | `[]` | Exact SANE device names, connection details, backend packages and display names. |
| `scanservjs_retention_days` | With scanner | None | Days to retain completed scans, from `1` to `900`. |
| `scanservjs_ocr_languages` | With scanner | `[eng]` | Tesseract language codes, such as `[eng, deu]`. |
| `scanservjs_port` | With scanner | `8080` | ScanservJS TCP port, from `1` to `65535`. |
| `scanservjs_page_splitting` | No | `false` | Also writes one PDF per scanned page. |
| `enable_remote_sane` | No | `false` | Enables SANE-native access for trusted-LAN clients. |
| `enable_unattended_upgrades` | No | `false` | Enables unattended security updates without automatic reboot. |

### Printer Connections

| Connection | Use | Notes |
| --- | --- | --- |
| `ipp` or `ipps` | Driverless network printer | Preferred connection. |
| `socket` | JetDirect or AppSocket printer | Uses TCP port `9100` and normally needs a package profile. |
| `lpd` | Older network printer | Requires the remote queue name; the server does not provide LPD. |
| `usb` | Locally connected printer | Requires either `ipp_usb` or `legacy_usb`. |

For `driver_mode: package_profile`, the queue also requires a `package_profile` and an exact `cups_model`. Onboarding installs the selected profile, then offers only CUPS models currently advertised by the server. It never selects a model automatically. The registry combines hand-maintained profiles with a generated catalog captured from the target's own distribution packages; a suggestion appears only on an exact `printer-device-id` make-and-model match, and the operator still selects the exact model.

### Device Topologies

| Topology | Use when | Notes |
| --- | --- | --- |
| `network` | The device connects to the normal router or switch. | The default path for IPP printing and standard network scanning. |
| `direct_ethernet` | The device connects to an unused server Ethernet interface. | Uses a private IPv4 `/30` outside the trusted LAN. |
| `usb` | The device connects locally to the server. | Printing is common; scanning depends on a working SANE backend. |

A direct Ethernet link needs a static address on the device. For example, configure server `192.168.50.1/30` and device `192.168.50.2`. This project does not enable DHCP on the link or route it to trusted-LAN clients.

### Scanner Settings

`managed_scanners` uses the exact SANE identifier returned by `scanimage -L`. A network scanner may use `network`, `ipp` or `ipps`. A USB scanner must explicitly choose `ipp_usb` or `legacy_usb`. `display_name` replaces the raw SANE identifier in ScanservJS.

Set `backend_install: false` only when a backend is installed and maintained outside this project. The deployment still installs `sane-utils` and validates the configured identifier, but does not install or update that backend.

Remote SANE is disabled by default and is intended for compatible native clients. Browser scanning through ScanservJS is the supported path for mixed client environments.

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
    display_name: Office Scanner
scanservjs_retention_days: 90
scanservjs_ocr_languages: [eng, deu]
scanservjs_port: 8080
scanservjs_page_splitting: false
enable_remote_sane: false
```

## How it Works

The repository treats the inventory as the desired state for the server. It does not aim to replace every local administrator decision. It owns only the CUPS queues, firewall rules and direct Ethernet links that it created, so later runs can remove stale project resources without resetting unrelated configuration.

1. `scripts/onboard` runs on the administrator machine. It validates the connection, collects non-secret settings and writes production inventory only after review.
2. The `site.yml` playbook connects over SSH. It validates the supported Debian version and CPU architecture, configures the administrator account and SSH, manages update policy and applies the trusted-LAN firewall rules.
3. CUPS reconciles the declared printer queues. Shared queues are advertised through Avahi and link-local DNS-SD, while CUPS administration stays localhost-only.
4. Scanner definitions install the selected SANE backend and ScanservJS. ScanservJS receives its pinned package version, OCR languages, retention timer and storage checks from inventory.
5. A commissioning run requires every declared printer and scanner to answer through its configured endpoint or SANE backend. A normal maintenance run preserves existing queues and reports unavailable hardware instead of treating a temporary outage as a configuration change.
6. `scripts/manage-devices` changes one definition at a time. It creates a local backup, saves the intended state and then offers to apply it to the server.

## Installation & Development

1. **Clone the repository**

   ```bash
   git clone https://github.com/jasonhaak/auto-print-scan-server.git
   cd auto-print-scan-server
   ```

2. **Install dependencies**

   ```bash
   ./scripts/setup
   ```

3. **Configure a production server**

   ```bash
   ./scripts/onboard
   ```

4. **Apply the current production inventory**

   ```bash
   ./scripts/manage-devices apply
   ```

For an overview of the available commands, run:

```bash
./start help
```

## Testing

The repository uses Bash tests, Python tests, `yamllint` and `ansible-lint`. Run the complete local suite with:

```bash
./scripts/qa
```

The suite checks onboarding and device-management behaviour, inventory handling, role logic, YAML and Ansible conventions and playbook syntax. Follow [acceptance testing](docs/acceptance-testing.md) for server, printer, scanner, DNS-SD and firewall checks on real hardware.

## Author & Licence

This code was written by Jason Haak and is licensed under the MIT licence.
