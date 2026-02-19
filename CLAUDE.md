# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESP32APRS Audio HARC is an APRS (Automatic Packet Reporting System) firmware for ESP32 microcontrollers implementing an IGate, Digipeater, GPS Tracker, Weather Station, and Telemetry system with a built-in AFSK/GFSK software TNC. Originally by HS5TQA/Atten, this fork targets HARC weather station use.

**Target hardware:** ESP32-S3 (primary), also ESP32, ESP32-C3, ESP32-C6, ESP32-S2.

## Build Commands

This is a PlatformIO project. The default build environment is `esp32-s3-devkitc1-n8r2`.

```bash
pio run                          # Build (default env)
pio run -e esp32-s3-devkitc1-n8r2  # Build specific environment
pio run --target upload          # Flash firmware
pio run --target monitor         # Serial monitor (115200 baud)
pio run --target clean           # Clean build
```

Available environments: `esp32-s3-devkitc1-n8r2`, `esp32-s3-devkitc1-n16r8`, `esp32-s3-devkitc-1-n32r8v`, `waveshare_esp32_s3_zero`.

## Architecture

### FreeRTOS Task Model

The firmware runs concurrent FreeRTOS tasks defined in `src/main.cpp`:
- **taskNetwork** — WiFi, APRS-IS connection, WireGuard VPN, PPPoS
- **taskAPRS** / **taskAPRSPoll** — APRS packet processing, routing, and timing
- **taskSerial** — Serial I/O for GPS, TNC, AT commands
- **taskGPS** — GPS data parsing (TinyGPS++)
- **taskSensor** — Sensor polling and data collection

### Key Source Files

| File | Role |
|------|------|
| `src/main.cpp` (421KB) | Application entry, task setup, main loop, APRS routing |
| `src/webservice.cpp` (393KB) | Web configuration UI, WebSocket server |
| `src/config.cpp` | Configuration load/save (LittleFS, JSON) |
| `src/parse_aprs.cpp` | APRS packet parsing and decoding |
| `src/igate.cpp` | RF↔Internet gateway logic |
| `src/digirepeater.cpp` | Digipeater with path control |
| `src/weather.cpp` | Weather station with 26+ sensor types |
| `src/sensor.cpp` (50KB) | Sensor drivers (BME280, Modbus, Dallas, analog, etc.) |
| `src/handleATCommand.cpp` (87KB) | AT command interface (UART/MSG/BLE) |
| `src/message.cpp` | APRS messaging with AES encryption |
| `src/wireguard_vpn.cpp` | WireGuard VPN support |

### Core Library: `lib/LibAPRS_ESP32/`

The TNC/modem library implements:
- **AFSK.cpp** — Audio modem (1200bps Bell 202, 300bps Bell 103, V.23, 9600bps G3RUH)
- **AX25.cpp** — AX.25 protocol framing, HDLC, CRC
- **KISS.cpp** — KISS protocol for TNC interface
- **modem.cpp** — Multi-modem management
- **fx25.cpp** — FX.25 forward error correction

### Configuration

- Structures defined in `include/config.h`
- Stored on LittleFS filesystem as `/default.cfg`
- Default config template: `data/default.cfg`
- Web UI at port 80, WebSocket at port 81
- AP mode default: SSID `ESP32APRS_Audio`, IP `192.168.4.1`
- **Backup/Restore:** The File page (`/storage`) supports downloading and uploading files. Download `default.cfg` to back up the config; upload a saved copy (using "Save as: `default.cfg`") and reboot to restore it.

### Conditional Compilation Flags

Defined in `platformio.ini` per environment:
- `ENABLE_FX25` — FX.25 error correction
- `RFMODULE` — RF module (SA868/Sunrise) support
- `OLED` / `SH1106` — Display support
- `BLUETOOTH` — BT SPP/BLE
- `PPPOS` — GSM/cellular modem
- `MQTT` — MQTT client
- `DEBUG` — Debug serial output

### Modbus Sensor Interface

Implemented in `src/sensor.cpp` using the `eModbus` library (local copy in `lib/eModbus/`). See `doc/Modbus_Sensors.md` for full usage documentation.

**Note:** Due to the migration to a local copy of the eModbus library, only Modbus TCP (channel 4) is currently supported. Modbus RTU (serial) support is TBD — the eModbus `ModbusClientRTU::begin()` requires `HardwareSerial&`, which is incompatible with `HWCDC` on ESP32-S3. RTU code is compiled out (`#if 0` in `main.cpp`).

Global config fields in `include/config.h`:
- `modbus_enable` — enable the Modbus bus
- `modbus_channel` — transport: `1` = UART0, `2` = UART1, `3` = UART2 (RTU), `4` = TCP
- `modbus_de_gpio` — RS-485 DE (driver enable) GPIO, `-1` if unused (RTU only)
- `modbus_tcp_host` — IP address of Modbus TCP server/gateway (TCP only)
- `modbus_tcp_port` — Modbus TCP port, default 502 (TCP only)

Each sensor slot (`SensorInfo` in `include/sensor.h`) uses these port types:
- **`PORT_MODBUS_16` (24)** — reads 1 holding register (16-bit value)
- **`PORT_MODBUS_32` (25)** — reads 2 holding registers (big-endian 32-bit: MSB first, LSB second)

Both use Modbus function code 03 (`readHoldingRegisters`) via `syncRequest()`.

**Address encoding:** The `address` field packs slave address and register into one value:
`address = (slave_addr * 1000) + register_addr`. For example, register 42 on slave 1 = `1042`.

Raw values are transformed by the equation `a*v² + b*v + c` using the `eqns[3]` coefficients.

The `modbusRead()` helper in `src/sensor.cpp` abstracts RTU vs TCP — it checks `config.modbus_channel` and dispatches to the appropriate eModbus client.

**Companion server:** The ESP32-S3-WX-Modbus project at `/Users/rick/Sync/Projects/PlatformIO/ESP32-S3-WX-Modbus` provides the Modbus TCP server. See its `CLAUDE.md` for register map and client configuration details.

### Web UI Live Updates

The sensor monitor page (`/sensor`) auto-refreshes sensor values via a lightweight JSON endpoint:
- **`/sensordata`** (GET) — Returns a JSON array of current `sen[].sample` values (e.g. `[12.34, 0.00, ...]`)
- The sensor page polls this endpoint every 5 seconds using `$.getJSON` and updates the `sVal0`–`sVal9` input fields
- Handler: `handle_sensordata()` in `src/webservice.cpp`

Other pages use similar patterns: sidebar info reloads every 10s via `/sidebarInfo`, system info every 60s via `/sysinfo`.

### Startup Timing

Boot to WiFi-responsive takes ~7-25 seconds. The main delays in order:
1. **3s** — Splash/boot countdown in `setup()` (`delay(1000)` x3, lines ~3315-3344) — factory-reset BOOT button window
2. **1s** — `WiFi.mode(WIFI_OFF)` + `delay(1000)` in `wifiConnection()` (line 7719)
3. **2-10s** — `wifiMulti.run(10000)` WiFi scan/connect timeout (line 7749)
4. **~1s** — NTP sync and web service init in `taskNetwork`

### Partition Tables

Custom partition CSVs in project root (`flash_default_8MB.csv`, `flash_default_16MB.csv`, `flash_default_32MB.csv`) with dual OTA slots and SPIFFS.

## Important Notes

- `main.cpp` and `webservice.cpp` are very large files (400KB+). Read specific sections rather than the entire file.
- Pin assignments are hardware-dependent and configured at runtime via the web UI or AT commands.
- The project uses libraries bundled in `lib/` (not fetched from registries) alongside PlatformIO library dependencies in `platformio.ini`.
- APRS weather wind speed is currently converted kph to knots (`× 0.5399` in `weather.cpp`) instead of mph (`× 0.621`) as a workaround for receivers that interpret the field as knots.
