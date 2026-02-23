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
- **taskNetwork** — WiFi, APRS-IS connection, WireGuard VPN, PPPoS (core 1, priority 1)
- **taskAPRS** — APRS packet processing, routing, TX/RX (core 1, priority 2)
- **taskAPRSPoll** — Modem polling / audio sampling (core 1, priority 0)
- **taskSerial** — Serial I/O for GPS, TNC, AT commands (core 0, priority 5)
- **taskGPS** — GPS data parsing via TinyGPS++ (core 0, priority 4)
- **taskSensor** — Sensor polling and data collection (core 0, priority 6)

On ESP32-S3 (Xtensa dual-core), the APRS and network tasks share core 1 while utility tasks run on core 0. The AsyncWebServer (async_tcp) also runs on core 0, which means web request handlers execute on a different core than the APRS/network tasks.

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
- `CORE_DEBUG_LEVEL` — ESP-IDF log verbosity: 0=None, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Verbose. Set in `[env] build_flags`. Level 3 is recommended for normal use; level 4 enables `log_d()` (very chatty — 386 calls across codebase, may affect modem timing).

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

**Companion server:** The [ESP32-S3-WX-Modbus](https://github.com/RocketManRC/ESP32-S3-WX-Modbus) project provides the Modbus TCP server. The gateway connects via its access point at `192.168.4.2` (port 502). See its `CLAUDE.md` for register map and client configuration details.

### Web UI Live Updates

The sensor monitor page (`/sensor`) auto-refreshes sensor values via a lightweight JSON endpoint:
- **`/sensordata`** (GET) — Returns a JSON array of current `sen[].sample` values (e.g. `[12.34, 0.00, ...]`)
- The sensor page polls this endpoint every 5 seconds using `$.getJSON` and updates the `sVal0`–`sVal9` input fields
- Handler: `handle_sensordata()` in `src/webservice.cpp`

Other pages use similar patterns: sidebar info reloads every 10s via `/sidebarInfo`, system info every 60s via `/sysinfo`.

**Dashboard SSE (Server-Sent Events):** The Last Heard table and Chat messages are pushed via `AsyncEventSource` endpoints `/eventHeard` and `/eventMsg`. The `event_lastHeard()` function builds a full HTML table (~10-30KB) from `pkgList[]` on each update. To avoid wasting CPU and memory when no browser is viewing the dashboard, both functions skip all work when `count() == 0` (no SSE clients connected). The HTML buffer allocation uses `ps_calloc` (PSRAM) to avoid fragmenting the limited internal SRAM. On initial SSE connect, the `onConnect` callback sends the current table immediately (`gethtml=true` path), so no data is lost when reopening the dashboard.

### Dashboard DX Column

The DX column on the dashboard (`/` route, `webservice.cpp`) shows distance and bearing to each station whose packet contains a position (`F_HASPOS`). Computed in `webservice.cpp:1071-1086`:

1. **Local position** — uses GPS if valid, otherwise `config.igate_lat` / `config.igate_lon`
2. **Distance** — Haversine formula in `ParseAPRS::distance()` (`parse_aprs.cpp:73-92`), result in km (Earth radius = 6366.71 km)
3. **Bearing** — `ParseAPRS::direction()` (`parse_aprs.cpp:42-71`), aviation formula, result in degrees 0-360°
4. **Display** — `{dist}km/{bearing}°` (e.g. `12.3km/045°`), or `-` if the packet has no position

A **Filter DX** setting (`config.filterDistant`) on the dashboard config page limits displayed packets by distance (0 = no filter).

### Serial Console / Debug Output

On ESP32-S3 with `ARDUINO_USB_CDC_ON_BOOT=1`, `Serial` maps to **HWCDC** (native USB CDC). ESP-IDF log output (`log_e`/`log_w`/`log_i`/`log_d`) appears on both the native USB port and the COM port (UART0 via USB-UART bridge). Use either port for monitoring at 115200 baud.

**UART initialization:** Serial0/1/2 are guarded by `config.uartN_enable && config.uartN_baudrate > 0`. Without this guard, a baud rate of 0 triggers auto-detect which spams `Could not detect baudrate` errors.

**Status monitoring:** `taskNetwork` logs a `[STATUS]` line every 60 seconds with uptime, free heap (internal + PSRAM), WiFi state, and RX/TX packet counts. Watch for:
- Declining `heap` values → memory leak
- `wifi=0` → WiFi disconnection
- `rxCount` stops incrementing → packet processing stalled

### Startup Timing

Boot to WiFi-responsive takes ~7-25 seconds. The main delays in order:
1. **3s** — Splash/boot countdown in `setup()` (`delay(1000)` x3, lines ~3315-3344) — factory-reset BOOT button window
2. **1s** — `WiFi.mode(WIFI_OFF)` + `delay(1000)` in `wifiConnection()` (line 7719)
3. **2-10s** — `wifiMulti.run(10000)` WiFi scan/connect timeout (line 7749)
4. **~1s** — NTP sync and web service init in `taskNetwork`

### Status LED

A NeoPixel (WS2812) RGB LED or dual discrete LEDs provide visual status:

**Startup countdown** (3s BOOT button factory-reset window):
1. Red — 1 second
2. Green — 1 second
3. Blue — 1 second

If BOOT is held during this window, the LED flashes white (factory reset mode).

**Normal operation:**
- **Red** — Transmitting (PTT active)
- **Green** — Receiving (DCD — data carrier detected on RF)
- **Off** — Idle

LED control is in `LED_Status2()` in `lib/LibAPRS_ESP32/AFSK.cpp`, called from `setPtt()` (TX) and `setDcd()` in `modem.cpp` (RX). A 100ms rate-limit prevents NeoPixel flickering. Note: without an audio input or squelch signal, ADC noise can cause false DCD (green LED on intermittently) — this is normal modem behavior, not a bug.

Fallback for boards without NeoPixel: red LED on GPIO 4 (TX), green LED on GPIO 2 (RX).

### Shared Data and Concurrency

The `pkgList` (received packet history) and `txQueue` (TX packet queue) arrays are accessed from multiple tasks and from AsyncWebServer handlers running on different cores. Access is protected by a FreeRTOS mutex (`psramMutex`) in `src/main.cpp`:

- **`psramLock(timeout)`** — acquires mutex, default `portMAX_DELAY` (wait forever)
- **`psramUnlock()`** — releases mutex
- Mutex created in `setup()` via `xSemaphoreCreateMutex()` before task creation

Functions that hold the mutex: `getPkgList()`, `pkgListUpdate()`, `pkgTxPush()`, `pkgTxSend()`, `pkgTxDuplicate()`, `sort()`, `sortPkgDesc()`, and in `message.cpp`: `pkgMsgSort()`, `getMsgList()`, `pkgMsgUpdate()`.

**Important:** `pkgTxSend()` intentionally releases the mutex before both RF transmission (`APRS_sendTNC2Pkt`) and INET transmission (`aprsClient.write`) and re-acquires afterward, to avoid holding the lock during slow I/O. The INET path copies packet data to a local buffer before releasing the lock.

The `event_lastHeard()` function in `webservice.cpp` calls `getPkgList()` up to `PKGLISTSIZE` times (30 on PSRAM boards) to build the dashboard HTML. It runs from both taskNetwork (SSE push every ~1s) and AsyncWebServer handlers (SSE client connect on core 0).

### TX/RX Mode Switching

The modem switches between RX (ADC sampling) and TX (DAC output) modes. The ADC path differs by chip:

**ESP32 vs ESP32-S3 ADC paths** (`AFSK.cpp`):
- **ESP32** (`ADC_SAMPLE` defined): Timer-based `sample_adc_isr()` pushes to FIFO, gated by `if(!hw_afsk_dac_isr)`. `AFSK_TimerEnable()` starts/stops the timer.
- **ESP32-S3** (`ADC_SAMPLE` not defined): DMA-based `s_conv_done_cb()` callback from `adc_continuous` driver. `AFSK_TimerEnable()` is a no-op (code commented out in `#else` branch). The callback is gated by `if(hw_afsk_dac_isr) return true;` to prevent FIFO fill during TX.

**`ModemTransmitStart()`** (task context): Calls `setPtt(true)`, sets `hw_afsk_dac_isr = true` (gates ADC FIFO fill), stops ADC timer via `AFSK_TimerEnable(false)`, starts DAC timer.

**`ModemTransmitStop()`** (DAC timer ISR context, called from `Ax25GetTxBit()`):
1. Stops DAC timer
2. Flushes FIFO via `AFSK_FlushFifo()` (discards stale samples while gate is still closed)
3. Clears `hw_afsk_dac_isr` (re-enables ADC FIFO filling)
4. Calls `AFSK_TimerEnable(true)` (restarts ADC timer on ESP32, no-op on S3)
5. Sets `pttOff = true` for deferred PTT release

**Deferred PTT pattern:** `setPtt(false)` cannot be called from ISR context because it triggers `LED_Status2()` → `strip->show()` (NeoPixel RMT write), which overflows the ISR stack. Instead, `ModemTransmitStop()` sets `volatile bool pttOff = true`, and the `taskAPRS` loop picks this up within 10ms to call `setPtt(false)` from task context.

The shared flags `adcEn`, `dacEn` (`volatile int8_t`), `hw_afsk_dac_isr`, and `pttOff` (`volatile bool`) are declared in `AFSK.cpp` and **must** be `volatile` since they're written from ISR context and read from task context.

### RX Frame Buffer

The modem stores decoded frames in a small circular buffer in `lib/LibAPRS_ESP32/AX25.cpp` (`FRAME_MAX_COUNT`: 10 on ESP32-S3, 5 on others). If `taskAPRS` doesn't consume frames fast enough, new frames are dropped with `log_w("RX frame buffer full")`. The green DCD LED will still flash since carrier detection is independent of frame buffering.

### Partition Tables

Custom partition CSVs in project root (`flash_default_8MB.csv`, `flash_default_16MB.csv`, `flash_default_32MB.csv`) with dual OTA slots and SPIFFS.

## Important Notes

- `main.cpp` and `webservice.cpp` are very large files (400KB+). Read specific sections rather than the entire file.
- Pin assignments are hardware-dependent and configured at runtime via the web UI or AT commands.
- The project uses libraries bundled in `lib/` (not fetched from registries) alongside PlatformIO library dependencies in `platformio.ini`.
- APRS weather wind speed is currently converted kph to knots (`× 0.5399` in `weather.cpp`) instead of mph (`× 0.621`) as a workaround for receivers that interpret the field as knots.
