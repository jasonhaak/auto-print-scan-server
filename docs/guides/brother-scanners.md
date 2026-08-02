# Troubleshoot Brother scanners with brscan2

Use this guide when a Brother printer is reachable from Raspberry Print Server but scanning does not work through the standard SANE path. It explains how to establish whether brscan2 is a suitable manual fallback, configure a verified Brother model and prove a real scan.

This is experimental operator guidance. It does not add Brother support to onboarding, install software automatically or claim that all Brother models work.

The Brother MFC-7360N on Debian 13 arm64 is a tested example. Its network scanner works through the `brother` SANE backend. Its discovered WSD AirScan device was not usable: opening `airscan:w0:Brother MFC-7360N` returned `Invalid argument`.

## Decide whether brscan2 is needed

Start with normal onboarding. It remains the supported, brand-agnostic route for printers and scanners.

| Observation | Meaning | Next step |
| --- | --- | --- |
| `scanimage -L` reports a usable scanner and a real test scan succeeds | Standard SANE support works. | Keep the standard setup. Do not install brscan. |
| A WSD or eSCL scanner appears but an explicit scan cannot open it or produce an image | Discovery works, but that SANE backend is not usable for the device. | Consider brscan2 only if the exact Brother model has verified brscan2 data. |
| `sane-find-scanner` sees USB hardware but `scanimage -L` has no device | Hardware presence is only a discovery hint. | Find a compatible backend and exact model data. `sane-utils` alone is not a device driver. |
| A `brother:` scanner appears but the scan fails | The backend can address the device, but its model record, transport or scanner state may be wrong. | Check the registration file, device address and model data, then run one controlled test scan. |

Do not infer support from a similar model name. A brscan2 record includes the USB product ID, scanner function type and, for some models, endpoint values. Those values must come from Brother package data or another verified source.

## Use a brscan build that contains the model

The external project is [dmikushin/brscan](https://github.com/dmikushin/brscan). It supplies the `brother` SANE backend and publishes releases for ARM architectures.

Check the model data before installing a release or build. The MFC-7360N record below is currently a local addition and is not part of upstream `v1.0.1`. Installing that release alone does not enable this model.

The brscan repository needs these changes before its release artifacts are a general Raspberry Print Server dependency:

- make suffix-2 library symlinks respect `DESTDIR` during staged installation;
- make the installed backend visible to the dynamic linker, so `brsaneconfig` works without `LD_LIBRARY_PATH`;
- make the legacy libusb dependency clear and reproducible on current Debian; and
- validate every installed `models2/*.ini` record automatically.

Until then, use a reviewed local build or a later upstream release that demonstrably contains the required model data and fixes.

## Direct Ethernet example

For a device cabled directly to an unused Raspberry Pi Ethernet port, use a private `/30` link. The tested MFC-7360N configuration is:

| Side | IPv4 configuration |
| --- | --- |
| Raspberry Pi | `192.168.50.1/30` |
| MFC-7360N | `192.168.50.2` |
| MFC subnet mask | `255.255.255.252` |
| MFC gateway | `0.0.0.0` |

The Raspberry Print Server onboarding flow creates this link temporarily for discovery, then creates it permanently only after confirmation. Confirm the device is reachable before configuring a scanner:

```bash
ssh jason@192.168.178.33 'ping -c 3 192.168.50.2'
```

Replace the SSH address and device address with the values for the installation.

## Printing

Treat printing separately from scanning. The MFC-7360N does not provide usable IPP printing on this link. Its CUPS SNMP result provided this LPD endpoint:

```text
lpd://BRN30055C7A50D3/BINARY_P1
```

In onboarding, select `lpd` and the `brlaser` package profile. This printer configuration does not install or depend on brscan.

## Confirm the brscan2 model data

The installed brscan source or package must contain a model record under `/usr/share/sane/brother/models2/`. For the tested MFC-7360N, the file is `MFC-7360N.ini`:

```ini
[Support Model]
0x0270,13,1,"MFC-7360N",133,4
```

The brscan backend used for this test is compiled with `BRSANESUFFIX=2`. It loads all `models2/*.ini` records and then reads `Brsane2.ini`. `Brsane2.ini` should remain a symlink to the shared `Brsane.ini`; a one-model replacement would remove the existing base records.

## Register the scanner

After the matching brscan2 backend and model data are installed, enable the backend and register the network device. The tested installation placed the backend under `/usr/lib/sane`, so the registration command needs that library directory until brscan packaging is corrected.

```bash
ssh -t jason@192.168.178.33 \
  'sudo sh -c "grep -qxF brother /etc/sane.d/dll.conf || echo brother >> /etc/sane.d/dll.conf"'

ssh -t jason@192.168.178.33 \
  'sudo env LD_LIBRARY_PATH=/usr/lib/sane /usr/bin/brsaneconfig -a name=MFC7360N model=MFC-7360N ip=192.168.50.2'

ssh jason@192.168.178.33 \
  'sudo cat /usr/share/sane/brother/brsanenetdevice2.cfg'
```

For the tested device, the resulting configuration is:

```text
DEVICE=MFC7360N , "MFC-7360N" , 0x4f9:0x270 , IP-ADDRESS=192.168.50.2
```

Use the exact model name from the installed model record. A different Brother model needs its own verified record and registration values.

## Verify a real scan

First list the devices:

```bash
ssh jason@192.168.178.33 'scanimage -L'
```

For the MFC-7360N, the verified Brother network identifier was `brother:net1;dev0`. A different model or transport can report another identifier, so copy the exact `brother:` value from the preceding command. Run a physical scan and validate the resulting file:

```bash
ssh jason@192.168.178.33 \
  "scanimage -d 'brother:net1;dev0' --mode Gray --resolution 200 --format=png > /tmp/mfc7360n-network.png && file /tmp/mfc7360n-network.png && stat -c '%s bytes' /tmp/mfc7360n-network.png"
```

Success means the scanner moves and the command reports a non-empty image file. The tested scans produced 1648 x 2291, 1-bit grayscale PNG files.

## Current limitations

- This is a manual experimental setup. Raspberry Print Server does not install, update or persist brscan configuration through onboarding.
- Additional Brother models require verified model data and a real hardware scan. Do not add a bulk list based only on model names.
- A later upstream brscan release containing the required model data and packaging fixes can replace this manual path.
