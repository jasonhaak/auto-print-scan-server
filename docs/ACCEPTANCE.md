# Commissioning acceptance

Commission a fresh Raspberry Pi OS Lite 64-bit host based on Debian Trixie by running the
onboarding wizard from Linux, macOS or WSL2:

```bash
scripts/onboard
```

The wizard writes non-secret production inventory, installs the pinned Ansible collections and
runs commissioning. Passwords stay interactive and are never written to inventory.

## Manual commissioning

Use this sequence when inventory has already been prepared:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml -e print_server_commissioning=true
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml
```

The last run should report no changes apart from refreshed package metadata. A commissioning run
fails when a declared printer or scanner is unavailable. Routine maintenance preserves the
managed queue and reports unavailable hardware instead of deleting it.

## Functional checks

Run only checks relevant to the declared hardware:

```bash
lpstat -v
avahi-browse --all --resolve --terminate | grep -E '_ipp._tcp|_printer._tcp'
curl --fail http://127.0.0.1:8080/api-docs
systemctl is-enabled scanservjs-retention.timer
sudo ufw status numbered
```

Verify that a trusted-LAN client can print and browse ScanservJS, while a client outside
`trusted_lan_cidrs` cannot reach IPP, ScanservJS or optional remote SANE. When remote SANE is
enabled, verify one Linux SANE client with `scanimage -L`.

Test the configured printer with a CUPS test page. Test a scanner by producing a PDF through
ScanservJS and confirm that it appears in the configured output directory. The `brlaser` profile
and every physical printer or scanner remain unvalidated until this hardware acceptance is
recorded.

## Recovery

Recover by flashing fresh Trixie Lite 64-bit media, enabling SSH and recreating the bootstrap
account with Raspberry Pi Imager. Restore the production inventory from version control or
`.onboard-backups/`, then rerun commissioning. Scan-file backup and external backup transport
are outside this repository's scope.
