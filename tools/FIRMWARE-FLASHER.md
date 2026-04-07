# ESP32APRS Audio HARC Firmware Flasher

Browser-based firmware flasher for ESP32APRS Audio HARC (ESP32-S3). Uses Espressif's [esptool-js](https://github.com/espressif/esptool-js) library with the WebSerial API — no software installation required.

## Requirements

- **Chrome or Edge** browser (WebSerial is not supported in Safari or Firefox)
- USB cable connected to the ESP32-S3 board
- A firmware `.bin` file (merged or standalone)

## Quick Start (End Users)

1. Connect the ESP32-S3 board to your computer via USB
2. Open `flash.html` in Chrome
3. Click **Connect** — Chrome will show a serial port picker, select the board's port
4. Select the firmware `.bin` file
5. Set flash address to **0x0 (merged image)**
6. Click **Flash Firmware**
7. Wait for completion — the board resets automatically

## Building Firmware

### Standard PlatformIO Build

```bash
cd /path/to/ESP32APRS_Audio_HARC
pio run                              # default env (esp32-s3-devkitc1-n16r8)
pio run -e esp32-s3-devkitc1-n8r2    # specific environment
```

Available environments: `esp32-s3-devkitc1-n8r2`, `esp32-s3-devkitc1-n16r8`, `esp32-s3-devkitc-1-n32r8v`, `waveshare_esp32_s3_zero`.

### Creating a Merged Binary

The merge script combines bootloader, partition table, boot app, and firmware into a single file that can be flashed at address 0x0:

```bash
./tools/merge_firmware.sh esp32-s3-devkitc1-n16r8
# Output: tools/ESP32APRS-esp32-s3-devkitc1-n16r8.bin

./tools/merge_firmware.sh esp32-s3-devkitc1-n8r2
# Output: tools/ESP32APRS-esp32-s3-devkitc1-n8r2.bin
```

The script auto-detects flash size from the environment name (4MB for waveshare_esp32_s3_zero, 8MB for n8r2, 16MB for n16r8, 32MB for n32r8v).

The script uses `esptool.py merge_bin` and requires Python 3 with esptool installed (`pip3 install esptool`).

### Flash Layout

| Address | File | Description |
|---------|------|-------------|
| 0x0000 | bootloader.bin | ESP32-S3 second-stage bootloader |
| 0x8000 | partitions.bin | Partition table |
| 0xE000 | boot_app0.bin | OTA boot selector |
| 0x10000 | firmware.bin | Application firmware |

A merged binary contains all four at their correct offsets and is flashed to address 0x0.

## Flash Address Selection

- **0x0 (merged image)** — Use this for merged `.bin` files created by `merge_firmware.sh`. This is the recommended option for distribution.
- **0x10000 (firmware only)** — Use this to flash just the application firmware (`.pio/build/<env>/firmware.bin`). Only use this if the bootloader and partition table haven't changed.

## Baud Rate

The default baud rate of 460800 works well for most setups. If you experience connection issues, try lowering to 230400 or 115200.

## Troubleshooting

### "No compatible devices found" in port picker
- Make sure the board is connected via USB and powered on
- Try a different USB cable (some cables are charge-only)
- ESP32-S3 DevKitC boards have two USB ports — use the one labeled "USB" (native USB), not "COM" (UART bridge)

### Connection timeout
- Try lowering the baud rate to 115200
- Hold the Boot button while clicking Connect (forces bootloader mode)
- On ESP32-S3 DevKitC: the Boot button is typically GPIO 0

### "WebSerial is not supported"
- Use Chrome or Edge. Safari and Firefox do not support WebSerial.

### Flash fails partway through
- Try a lower baud rate
- Ensure the USB connection is stable (avoid USB hubs if possible)
- Try again — the bootloader is resilient to interrupted flashes

### Board doesn't boot after flashing
- If you flashed firmware-only (0x10000) and the partition table changed, reflash using a merged image at 0x0
- Try the merge script to create a fresh merged binary

## Distribution

To distribute a firmware update to end users:

1. Build the firmware: `pio run -e esp32-s3-devkitc1-n16r8`
2. Create merged binary: `./tools/merge_firmware.sh esp32-s3-devkitc1-n16r8`
3. Zip together: `flash.html` + `ESP32APRS-esp32-s3-devkitc1-n16r8.bin`
4. Users open the HTML in Chrome and follow the Quick Start instructions

## Technical Details

- Uses [esptool-js v0.5.7](https://github.com/espressif/esptool-js) via jsDelivr CDN
- Communicates with the ESP32-S3 ROM bootloader via SLIP-framed serial protocol
- Automatically toggles RTS/DTR to enter bootloader mode
- Uploads a flash stub to the chip for faster flashing
- Supports compressed uploads for reduced transfer time
- Auto-resets the chip after flashing to run new firmware
