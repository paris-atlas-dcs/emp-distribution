# emp-distribution

Distribution packaging for the ATLAS DCS EMP (Embedded Monitoring Processor) board.

This repo assembles pre-built components from upstream repositories into deployable bundles. It contains no compiled code — only the manifest, site configs, systemd units, and deployment scripts.

## Architecture

**Two-tier deployment:**

1. **Base image** (rare, ~yearly) — full SD card image with OS, boot files, kernel modules, and a known-good software version. Flash once per board.
2. **Software update** (frequent) — lightweight tarball with OPC UA servers, CLI tools, and firmware overlay. Deployed over SSH with atomic symlink swap and instant rollback.

## Components

| Component | Upstream repo | What |
|-----------|--------------|------|
| OpcUaLpGbtServer | paris-atlas-dcs/OpcUaLpGbtServer | lpGBT front-end OPC UA server |
| psMonServer | paris-atlas-dcs/psmonserver | Crate PSU OPC UA server |
| LpGbtSw | paris-atlas-dcs/LpGbtSw | CLI demonstrator tools |
| epos-bsp | atlas-dcs-emp-epos/epos-bsp | Boot files (BOOT.BIN, kernel) |
| epos-rootfs | atlas-dcs-emp-epos/epos-rootfs | AlmaLinux 9 root filesystem |
| etools | atlas-dcs-emp-epos/etools | Firmware loading tools |
| fwlpgbt | paris-atlas-dcs/fwlpgbt | WinCC OA framework (SCADA side) |

## On-board layout

```
/opt/emp/
  current -> releases/2026.04.1/     # symlink, atomic swap
  releases/
    2026.04.1/                        # active version
      OpcUaLpGbtServer/bin/ + lib/
      psMonServer/bin/ + lib/
      tools/                          # CLI demonstrators
      firmware/                       # .dtbo + .bit.bin (if included)
      systemd/                        # service unit files
      manifest.yml                    # what's in this release
      version                         # plain text version string
    2026.03.5/                        # previous (rollback target)
  config/                             # per-board (never overwritten)
    config-lpgbt.xml
    config-psmon.xml
  version                             # current version string
```

## Usage

### Deploy a software update

```bash
./scripts/deploy.sh dcslab-emptest2 emp-2026.04.1.tar.gz
```

### Roll back to previous version

```bash
./scripts/rollback.sh emp-test2
```

### Add a new site

```bash
cp -r sites/_template sites/my-new-board
# Edit sites/my-new-board/config-lpgbt.xml with chip addresses and calibration
```

### Bump a component version

Edit `manifest.yml`, commit, push. CI assembles the new bundle automatically.
