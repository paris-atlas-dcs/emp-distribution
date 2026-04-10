# EMP Distribution

Complete software distribution for the ATLAS DCS EMP (Embedded Monitoring Processor) board.

## Quick Start

### New board (first time setup)

Download the latest image from EOS:
```
/eos/project/a/atlasdcsdata/ci-artifacts/emp-distribution/image/emp/
```

Flash it to an SD card:
```bash
gunzip emp-image-2026.04.6.img.gz
sudo dd if=emp-image-2026.04.6.img of=/dev/sdX bs=4M status=progress
sync
```

Insert the SD card and power on. The board will:
1. Expand the filesystem to fill the SD card (first boot only)
2. Load the FPGA firmware
3. Program the Si5345 clock
4. Reset the lpGBT controllers
5. Start all OPC UA servers

The board is operational within ~60 seconds. No manual configuration needed for the default setup.

### Update software on a running board

Download the latest software bundle from EOS:
```
/eos/project/a/atlasdcsdata/ci-artifacts/emp-distribution/software/
```

Deploy:
```bash
./scripts/deploy.sh dcslab-emptest2 emp-2026.04.6.tar.gz
```

This uploads the bundle, performs an atomic symlink swap, and restarts services. Zero-downtime preparation, ~5 seconds of actual switchover.

### Roll back

```bash
./scripts/rollback.sh emp-test2
```

One command. Swaps back to the previous version and restarts services.

## What's inside

### Software bundle (`emp-<version>.tar.gz`)

| Component | What it does |
|-----------|-------------|
| **OpcUaLpGbtServer** | OPC UA server for lpGBT front-end control and monitoring |
| **LpGbtSw CLI tools** | 17 command-line tools for direct lpGBT interaction (lpGbtIdentify, lpGbtAdc, etc.) |
| **psMonServer** | OPC UA server for crate power supply monitoring |
| **opcuaempmon** | OPC UA server for EMP baseboard monitoring (Firefly, SFP, temperatures) |
| **emp-tools** | Board-level tools: clock programmer, firmware reset, Firefly monitor |
| **systemd services** | Auto-start and boot ordering for all components |

### Full image (`emp-image-<version>.img.gz`)

Everything above, plus:
- AlmaLinux 9 operating system (aarch64)
- PetaLinux kernel modules
- FPGA firmware overlay
- Pre-configured systemd boot chain
- Auto-resize on first boot

## OPC UA endpoints

| Server | Port | What it monitors |
|--------|------|-----------------|
| OpcUaLpGbtServer | 21182 | lpGBT chips: temperature, ADC, I2C, GPIO, link status |
| psMonServer | 22486 | Crate PSU: voltages, currents, fan speed, temperatures |
| opcuaempmon | TBD | EMP board: Firefly optics, SFP, Si5345 clock, system temperatures |

## Boot sequence

On power-on, systemd starts services in this order:

```
emp-firstboot        (first boot only: expand filesystem)
      |
emp-firmware         (load FPGA device tree overlay)
      |
emp-clock            (program Si5345 clock generator)
      |               \
emp-reset             opcua-empmon
      |
opcua-lpgbt          opcua-psmon (independent)

tempMonitor.timer    (periodic Firefly temperature checks)
```

## On-board directory layout

```
/opt/emp/
  current -> releases/2026.04.6/     (atomic symlink swap)
  releases/
    2026.04.6/                        (current version)
      OpcUaLpGbtServer/
        bin/                          (server + configs)
        lib/                          (bundled shared libraries)
        tools/bin/                    (CLI demonstrators)
        tools/lib/                    (tool libraries)
      psMonServer/bin/ + lib/
      opcuaempmon/
      emp-tools/bin/ + lib/
    2026.03.5/                        (previous, for rollback)
  config/                             (site-specific, never overwritten)
  version                             (current version string)
```

## Site-specific configuration

The default image works out of the box with example configurations. For your specific setup:

1. Copy the template: `cp -r sites/_template sites/my-board`
2. Edit `sites/my-board/config-lpgbt.xml` with your chip addresses and calibration
3. Deploy the config: `scp config-lpgbt.xml board:/opt/emp/current/OpcUaLpGbtServer/bin/config-site.xml`
4. Restart: `ssh board sudo systemctl restart opcua-lpgbt`

Generate per-chip calibration coefficients:
```bash
python3 tools/lpgbt-cal-gen.py --db lpgbt_calibration.db --chipids YOUR_CHIP_IDS --tj 45
```

## Adding a new site

```bash
cp -r sites/_template sites/atlas-usa15-slot3
# Edit the config XML with chip addresses, vrefTune, calibration formulas
# Commit and push — the deploy script uses it automatically
```

## Building a new release

### Software only (frequent)

Edit `manifest.yml` to pin specific versions (or leave as `latest`), then:
```bash
./scripts/assemble.sh 2026.05.1
```

Or push to `main` — CI builds and uploads to EOS automatically.

### Full image (rare)

Trigger via GitHub Actions: Actions → Full Image → Run workflow → enter version and board.

## Testing

Run the full test suite locally:
```bash
./tests/run-all.sh emp-2026.04.6.tar.gz
```

Individual tests:
```bash
./tests/validate-bundle.sh emp-2026.04.6.tar.gz   # structure + integrity (instant)
./tests/validate-systemd.sh                         # boot chain ordering (instant)
./tests/smoke-test.sh emp-2026.04.6.tar.gz          # servers + tools in Docker QEMU (~60s)
```

## Repository structure

```
emp-distribution/
  .github/workflows/
    software-release.yml        (assembles software bundle → EOS)
    full-image.yml              (builds flashable SD card image → EOS)
  manifest.yml                  (component versions — source of truth)
  systemd/                      (all service + timer unit files)
  scripts/
    assemble.sh                 (local bundle assembly)
    deploy.sh                   (SSH deploy with atomic swap)
    rollback.sh                 (one-command rollback)
    loadFirmware.sh             (runtime FPGA overlay loading)
    emp-firstboot.sh            (first-boot filesystem expansion)
  sites/                        (per-board configuration)
  tests/                        (validation + smoke tests)
```

## Troubleshooting

**Server won't start**: Check `journalctl -u opcua-lpgbt` for errors. Common issues:
- Missing `config-site.xml` → copy from `config-example.xml`
- Port conflict → check `ServerConfig.xml` port settings
- Missing shared libs → verify `LD_LIBRARY_PATH` in service file

**Wrong temperatures**: Check `vrefTune` in config XML. Use `lpGbtIdentify` to read chip IDs, then look up calibration in the CERN database.

**FPGA not loading**: Check `systemctl status emp-firmware`. Verify `.dtbo` and `.bit.bin` are in `/lib/firmware/`.

**Rollback needed**: `./scripts/rollback.sh <hostname>` — swaps symlink to previous version.

## Contact

Paris Moschovakos — ATLAS DCS, CERN
