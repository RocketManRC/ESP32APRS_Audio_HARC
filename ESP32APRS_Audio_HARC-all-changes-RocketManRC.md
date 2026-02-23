## ESP32APRS_Audio_HARC — All Changes

### Modbus TCP Support (Feb 16)
- Migrated from ModbusMaster to eModbus library (local copy in `lib/`) to support Modbus TCP
- Added Modbus TCP configuration fields to web UI (host, port, channel)
- Gateway IP set to `192.168.4.2` (companion server's access point)

### Web UI Enhancements (Feb 19)
- **File upload/download** on storage page (`/storage`) with "Save as" field
- **Sensor auto-refresh** — `/sensordata` JSON endpoint, polled every 5s
- Config diff utility script (`cfgdiff.py`)

### Upstream Merge (Feb 19)
- Selective cherry-pick from upstream V1.7, skipping incompatible Modbus and duplicate upload changes
- Fixed `rom/crc.h` build failure on ESP32-S3/C3

### LED PTT Bug Fix (Feb 19)
- `LED_Status2()` debounce logic was inverted — red LED never lit during TX. Fixed.

### Debug Infrastructure (Feb 21)
- `CORE_DEBUG_LEVEL` changed from 0 to 3 (Info-level logging enabled)
- Added `[STATUS]` log every 60s (uptime, heap, PSRAM, WiFi, RX/TX counts)
- UART init guards on all three serial ports (prevent baudrate auto-detect spam)

### Concurrency Fix (Feb 21)
- Replaced broken `bool psramBusy` spinlock with FreeRTOS `psramMutex` (xSemaphoreCreateMutex)
- WebSocket cleanup (`ws.cleanupClients()`) to prevent stale client memory growth

### SSE Memory Optimization (Feb 21)
- `event_lastHeard()` and `event_chatMessage()` skip work when no SSE clients connected
- HTML buffer allocation moved to PSRAM (`ps_calloc`) to prevent internal SRAM fragmentation

### TX/RX Mode Switching Fix (Feb 22 — the big one)
- **RX freeze after TX on ESP32-S3** — added `hw_afsk_dac_isr` gate in `s_conv_done_cb()` to stop ADC FIFO fill during TX
- **FIFO flush** in `ModemTransmitStop()` to discard stale samples before resuming RX
- **ISR stack overflow** — deferred `setPtt(false)` out of ISR via `volatile bool pttOff`, polled by taskAPRS
- **Volatile flags** added to `adcEn`, `dacEn`, `hw_afsk_dac_isr` (ISR/task shared state)
- **CSMA improvement** — fix prevents TX during active RX, eliminating silent on-air collisions
- RX frame buffer increased (5→10 on S3, 3→5 on others)
- Validated: 16+ hours, 252 TX, 1115 RX, zero issues

### APRS-IS Packet Monitor (Feb 23 — new tool)
- `tools/aprs_monitor.html` — standalone browser-based APRS-IS monitor, no backend
- WebSocket connection with auto WS/WSS detection for HTTP/HTTPS hosting
- Decodes weather, position, message, telemetry, status, object packets
- Server-side filters (buddy/prefix/range) + client-side packet type filter
- Weather: wind in mph + km/h, temp in F + C
- Position: regex-based parsing handles 2 and 3 decimal place coordinates

### Documentation
- Created comprehensive `CLAUDE.md` for the project
- Created `doc/Modbus_Sensors.md`
- Filed upstream issue on `nakhonthai/ESP32APRS_Audio` for the TX/RX bugs
