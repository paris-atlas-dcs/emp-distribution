# EMP Distribution

Complete software package for the ATLAS DCS EMP (Embedded Monitoring Processor) board.

**EMP** is the back-end processing board for the ATLAS Detector Control System, based on a Zynq UltraScale+ ARM processor. It connects to front-end EMCI boards via optical links and runs OPC UA servers for monitoring and control.

## New Board Setup

### What you need

- An EMP board with an SD card slot
- A micro SD card (8 GB or larger)
- A computer with an SD card reader and a terminal
- The image file (`emp-image-<version>.img.gz`) — you should have received a download link

### Step 1: Identify your SD card

Insert the SD card into your computer and find its device name:

```bash
lsblk
```

Look for a device matching your SD card size (e.g. `/dev/sdb` or `/dev/mmcblk0`). **Not** your main disk.

### Step 2: Flash the image

> **WARNING**: The `dd` command will erase the target device. Double-check the device name. Writing to the wrong device will destroy data permanently.

```bash
gunzip emp-image-2026.04.6.img.gz
sudo dd if=emp-image-2026.04.6.img of=/dev/sdX bs=4M status=progress
sync
```

Replace `/dev/sdX` with your actual SD card device from Step 1.

### Step 3: Boot

Insert the SD card into the EMP board and power on. The board will automatically:

1. Expand the filesystem to fill the SD card (first boot only, ~30s)
2. Load the FPGA firmware
3. Program the clock generator
4. Reset the front-end controllers
5. Start all monitoring servers

The board is ready when the green LED is stable (~60 seconds).

### Step 4: Verify

From any machine on the same network:

```bash
ssh root@<board-ip>
cat /opt/emp/version
systemctl status opcua-lpgbt opcua-psmon
```

If power is lost during flashing, the SD card will be corrupted. Re-flash from Step 2.

## Software Updates

To update the software without reflashing the SD card:

```bash
# From your laptop — one command
./scripts/deploy.sh <board-hostname> emp-2026.04.6.tar.gz
```

This uploads the new version, installs it alongside the running version, then switches over instantly (~5 seconds of service restart). The previous version stays on the board for rollback.

### Rolling back

If something goes wrong after an update:

```bash
./scripts/rollback.sh <board-hostname>
```

This switches back to the previous version and restarts services. One command, instant.

## What's running on the board

### Servers

| Server | Port | What it monitors |
|--------|------|-----------------|
| OpcUaLpGbtServer | 21182 | lpGBT front-end chips: temperature, ADC, I2C, GPIO, link status |
| psMonServer | 22486 | Crate power supply: voltages, currents, fan speed, temperatures |
| opcuaempmon | 21183 | EMP board: Firefly optics, SFP modules, clock, board temperatures |

Connect from WinCC OA or UaExpert using: `opc.tcp://<board-ip>:<port>`

### Startup order

Services start automatically on boot in this order:

```
FPGA firmware load
      |
Clock programming (Si5345)
      |               \
Front-end reset       Board monitor (opcuaempmon)
      |
lpGBT server          PSU server (independent)

Temperature monitor (periodic, every 30s)
```

### Command-line tools

The board includes diagnostic tools that can be run directly via SSH:

```bash
# Identify connected lpGBT chips
lpGbtIdentify --scan

# Read ADC channels
lpGbtAdc -a lpgbt-uio://emp_lpgbt_0

# Check power supply voltages
lpGbtPowerMon -a lpgbt-uio://emp_lpgbt_0 -i 1

# Reset firmware
fwReset --ip emp_lpgbt --id 0
```

All tools are in `/opt/emp/current/OpcUaLpGbtServer/tools/bin/` and `/opt/emp/current/emp-tools/bin/`.

## Configuration

### Do I need to change the configuration?

**No**, if you are using a standard EMCI setup in the DCS lab. The default configuration works.

**Yes**, if:
- You have different lpGBT chip addresses than the default
- You need per-chip temperature calibration (for accurate readings)
- You are setting up a new site with different hardware

### Changing the lpGBT configuration

The configuration file is at:
```
/opt/emp/current/OpcUaLpGbtServer/bin/config-site.xml
```

Edit it with the correct chip addresses and calibration coefficients for your setup, then restart:

```bash
sudo systemctl restart opcua-lpgbt
```

An example configuration and a DCS lab configuration are included in the same directory.

### Generating calibration coefficients

Each lpGBT chip has unique calibration data. To get accurate temperature readings:

1. Read the chip ID: `lpGbtIdentify -a lpgbt-uio://emp_lpgbt_0`
2. Look up the chip ID in the CERN lpGBT calibration database
3. Generate the config snippet:
   ```bash
   python3 tools/lpgbt-cal-gen.py --db lpgbt_calibration.db --chipids <YOUR_CHIP_ID> --tj 45
   ```
4. Paste the output into your `config-site.xml`

### Checking firmware version

```bash
# Software version
cat /opt/emp/version

# Firmware overlay files
ls -la /lib/firmware/hw_desc.*

# FPGA manager status
cat /sys/class/fpga_manager/fpga0/state
```

## Troubleshooting

**Server won't start**
```bash
journalctl -u opcua-lpgbt --no-pager -n 20
```
Common causes: missing `config-site.xml` (copy from `config-example.xml`), port conflict with another server.

**Wrong temperature readings**
Check `vrefTune` in the config XML — this is the voltage reference trim value unique to each chip. Without correct calibration, temperatures can read ±50°C off. See "Generating calibration coefficients" above.

**FPGA not loading**
```bash
systemctl status emp-firmware
ls /lib/firmware/hw_desc.*
```
Both `hw_desc.bit.bin` and `hw_desc.dtbo` must be present in `/lib/firmware/`.

**Board not reachable on the network**
The board uses DHCP by default. Check your network's DHCP server for the board's assigned IP, or connect via serial console (115200 baud, USB-UART).

**Need to re-flash**
If the board is unresponsive, remove the SD card, re-flash from your computer (Step 2), and reinsert.

## Glossary

| Term | What it is |
|------|-----------|
| **lpGBT** | Low-Power Gigabit Transceiver — a CERN chip on the front-end boards, communicates with the EMP over optical fiber |
| **EMCI** | The front-end mezzanine board carrying one lpGBT + optical transceiver |
| **Firefly** | Samtec optical transceiver module on the EMP board (12-channel TX + RX) |
| **Si5345** | Silicon Labs clock generator chip on the EMP — must be programmed at boot |
| **vrefTune** | Voltage reference trim value (0-255) unique to each lpGBT chip, needed for accurate ADC readings |
| **OPC UA** | Open Platform Communications Unified Architecture — the protocol used by the monitoring servers |
| **WinCC OA** | The SCADA system used by ATLAS to display monitoring data from OPC UA servers |

## Contact

Paris Moschovakos — ATLAS DCS, CERN — paris.moschovakos@cern.ch
