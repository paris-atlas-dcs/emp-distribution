# EMP Distribution

Software distribution for the ATLAS DCS EMP board.

## Contents

- **OpcUaLpGbtServer** — lpGBT front-end OPC UA server (port 21182)
- **psMonServer** — crate PSU OPC UA server (port 22486)
- **opcuaempmon** — EMP board monitoring OPC UA server
- **emp-tools** — board tools: clock programmer, firmware reset, Firefly monitor
- **LpGbtSw CLI tools** — 17 command-line tools for lpGBT diagnostics
- **FPGA firmware overlay** — bitstream + device tree for runtime loading
- **Systemd services** — auto-start and boot ordering for all components

## Full Image (new board)

Flash `emp-epos-VERSION.img.gz` to an SD card:

```bash
lsblk                              # identify your SD card device
gunzip emp-epos-2026.04.1.img.gz
sudo dd if=emp-epos-2026.04.1.img of=/dev/sdX bs=4M status=progress
sync
```

> **WARNING**: Replace `/dev/sdX` with your SD card device. The wrong device will destroy data.

Insert the SD card, power on. Everything starts automatically. First boot takes ~60 seconds (filesystem expansion + service startup).

## Software Update (running board)

```bash
./scripts/deploy.sh <hostname> emp-release-2026.04.1.tar.gz
```

Installs alongside the running version, switches over instantly. Previous version kept for rollback.

## Rollback

```bash
./scripts/rollback.sh <hostname>
```

## Verify

```bash
ssh root@<board-ip>
cat /opt/emp/version
systemctl status opcua-lpgbt opcua-psmon opcua-empmon
```

## Documentation

Each component has its own documentation:

- [OpcUaLpGbtServer](https://github.com/paris-atlas-dcs/OpcUaLpGbtServer) — server configuration, calibration, address space
- [psMonServer](https://github.com/paris-atlas-dcs/psmonserver) — PSU monitoring setup
- [LpGbtSw](https://github.com/paris-atlas-dcs/LpGbtSw) — CLI tools reference
- [epos](https://github.com/paris-atlas-dcs/atlas-dcs-emp-epos) — OS, boot files, firmware tools

## Contact

Paris Moschovakos — ATLAS DCS, CERN
