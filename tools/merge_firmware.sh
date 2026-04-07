#!/bin/bash
# Merge PlatformIO build output into a single flashable .bin file
# Usage: ./tools/merge_firmware.sh [environment]
# Example: ./tools/merge_firmware.sh esp32-s3-devkitc1-n16r8

ENV="${1:-esp32-s3-devkitc1-n16r8}"
BUILD_DIR=".pio/build/$ENV"
BOOT_APP0="$HOME/.platformio/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin"
OUTPUT="tools/ESP32APRS-$ENV.bin"

if [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    echo "Error: $BUILD_DIR/firmware.bin not found. Run 'pio run -e $ENV' first."
    exit 1
fi

# Auto-detect flash size from environment name
case "$ENV" in
    *n32r8*)  FLASH_SIZE="32MB" ;;
    *n16r8*)  FLASH_SIZE="16MB" ;;
    *n8r2*)   FLASH_SIZE="8MB"  ;;
    *zero*)   FLASH_SIZE="4MB"  ;;
    *)        FLASH_SIZE="8MB"  ;;
esac

echo "Merging firmware for environment: $ENV (flash: $FLASH_SIZE)"
echo "  Bootloader:  $BUILD_DIR/bootloader.bin  @ 0x0000"
echo "  Partitions:  $BUILD_DIR/partitions.bin   @ 0x8000"
echo "  Boot app0:   boot_app0.bin               @ 0xE000"
echo "  Firmware:    $BUILD_DIR/firmware.bin      @ 0x10000"

/usr/bin/python3 -m esptool --chip esp32s3 merge_bin \
    --output "$OUTPUT" \
    --flash_mode dio \
    --flash_size "$FLASH_SIZE" \
    --flash_freq 80m \
    0x0000 "$BUILD_DIR/bootloader.bin" \
    0x8000 "$BUILD_DIR/partitions.bin" \
    0xe000 "$BOOT_APP0" \
    0x10000 "$BUILD_DIR/firmware.bin"

if [ $? -eq 0 ]; then
    SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
    echo ""
    echo "Success: $OUTPUT ($SIZE)"
    echo "Flash this file at address 0x0 using the web flasher."
else
    echo "Error: merge failed"
    exit 1
fi
