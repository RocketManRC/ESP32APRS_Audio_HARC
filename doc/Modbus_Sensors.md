# Modbus Sensor Interface

## Overview

The ESP32APRS Audio firmware supports reading sensors over Modbus using the `eModbus` library (local copy in `lib/eModbus/`). All Modbus sensors share a single global transport selected by the PORT setting. Implementation is in `src/sensor.cpp`. Configuration is done via the web UI or AT commands.

> **Note:** Only Modbus TCP is currently supported. Modbus RTU (serial) support is TBD — the eModbus `ModbusClientRTU::begin()` requires `HardwareSerial&`, which is incompatible with `HWCDC` (USB CDC) on ESP32-S3. The RTU code path is compiled out (`#if 0` in `main.cpp`). A future fix may restrict RTU to `Serial1`/`Serial2` or provide a wrapper.

## Configuration

Configure Modbus via the web UI under **MODBUS Modify** on the Sensor page.

### Global Settings

These fields in `include/config.h` control the Modbus bus:

| Field | Type | Description |
|-------|------|-------------|
| `modbus_enable` | `bool` | Enable/disable the Modbus bus |
| `modbus_address` | `uint8_t` | Default slave address (used by M701/M702/PZEM) |
| `modbus_channel` | `int8_t` | Transport: `1` = UART0, `2` = UART1, `3` = UART2 (RTU), `4` = TCP. `-1` = disabled |
| `modbus_de_gpio` | `int8_t` | GPIO for RS-485 DE (driver enable) pin. `-1` if unused. RTU only |
| `modbus_tcp_host` | `char[64]` | IP address of Modbus TCP server/gateway. TCP only |
| `modbus_tcp_port` | `uint16_t` | Modbus TCP port (default `502`). TCP only |

### RTU Mode (Serial) — TBD

> **Not currently supported.** RTU mode is compiled out due to incompatibility between eModbus `ModbusClientRTU::begin()` (requires `HardwareSerial&`) and ESP32-S3's `HWCDC` USB serial. See the note above.

When RTU support is restored, the configuration will be:

1. Set **PORT** to the UART connected to your RS-485 transceiver (`UART0`, `UART1`, or `UART2`).
2. Ensure the selected UART is enabled and configured with the correct baud rate on the UART settings page.
3. If your RS-485 transceiver has a DE (Driver Enable) pin, set the **DE** GPIO number. The firmware toggles this pin automatically during transmissions.
4. Set the **Address** to the Modbus slave address of your device.

### TCP Mode (Network)

1. Set **PORT** to `TCP`.
2. Enter the IP address of your Modbus TCP device or gateway in **TCP Host**.
3. Set **TCP Port** (default 502).
4. WiFi must be connected for TCP mode to function.

## Sensor Slot Configuration

Each sensor slot is a `SensorInfo` struct defined in `include/sensor.h`:

| Field | Type | Meaning for Modbus |
|-------|------|--------------------|
| `enable` | `bool` | Enable this sensor slot |
| `port` | `uint8_t` | Set to `PORT_MODBUS_16` (24) or `PORT_MODBUS_32` (25) |
| `address` | `uint16_t` | Encodes both slave address and register (see below) |
| `samplerate` | `uint16_t` | Polling interval in seconds |
| `averagerate` | `uint16_t` | Averaging window in seconds |
| `eqns[3]` | `float[3]` | Equation coefficients: `a*v² + b*v + c` applied to raw value |
| `unit` | `char[10]` | Display unit string (e.g., "°C", "hPa") |
| `parm` | `char[15]` | Sensor name/label |

## Address Encoding

The `address` field packs the Modbus slave address and register address into a single 16-bit value:

```
address = (slave_address * 1000) + register_address
```

At runtime the firmware splits them:
- **Slave address** = `address / 1000`
- **Register address** = `address % 1000`

**Examples:**

| Slave | Register | Address field |
|-------|----------|---------------|
| 1 | 0 | 1000 |
| 1 | 42 | 1042 |
| 2 | 100 | 2100 |
| 5 | 3 | 5003 |

This limits register addresses to 0-999 and slave addresses to 1-65.

## Port Types

### MODBUS_16Bit (`PORT_MODBUS_16` = 24)

- Reads **1 holding register** (Modbus function code 03)
- Returns a 16-bit unsigned value cast to `double`

### MODBUS_32Bit (`PORT_MODBUS_32` = 25)

- Reads **2 consecutive holding registers** (Modbus function code 03)
- Combines as big-endian 32-bit unsigned: first register = MSB, second register = LSB
- Result cast to `double`

## Value Transformation

After reading the raw value, the firmware applies the equation:

```
result = a * v² + b * v + c
```

Where `a`, `b`, `c` are the `eqns[3]` coefficients. For a direct passthrough, set `a=0, b=1, c=0`. To scale a raw value (e.g., divide by 10), set `a=0, b=0.1, c=0`.

## Hardware Wiring (RTU) — TBD

> RTU mode is not currently supported. This section is retained for when support is restored.

Connect the ESP32 UART to an RS-485 transceiver (e.g., MAX485, SP3485):

```
ESP32 TX  -->  RS-485 DI
ESP32 RX  <--  RS-485 RO
ESP32 DE  -->  RS-485 DE + RE (active high for transmit)
```

- TX/RX GPIOs are set via `uart1_tx_gpio`/`uart1_rx_gpio` (or uart0/uart2 depending on channel)
- DE GPIO is set via `modbus_de_gpio` (tie DE and RE together on the transceiver)

## Built-in Modbus Device Support

In addition to generic 16/32-bit register reads, the firmware has dedicated drivers for:

| Port Type | Device | Description |
|-----------|--------|-------------|
| `PORT_M701` (8) | M701 | Air quality sensor: CO2, CH2O, TVOC, PM2.5, PM10, Temperature, Humidity |
| `PORT_M702` (9) | M702 | Air quality sensor: TVOC, PM2.5, PM10, Temperature, Humidity |
| `PORT_PZEM` (23) | PZEM-004T | AC power meter: Voltage, Current, Power, Energy, Frequency, Power Factor |

These use the `modbus_address` field directly (not the packed encoding).

## Examples

### Reading a Wind Speed Sensor (RTU) — TBD

> RTU mode is not currently supported. This example is retained for when support is restored.

Suppose you have a Modbus RTU wind speed sensor at slave address 1, register 0, returning wind speed in tenths of m/s:

1. **MODBUS settings**: Enable, PORT = `UART1`, DE = your RS-485 DE pin
2. **Sensor slot**: Port = `MODBUS_16`, Address = `1000` (slave 1, register 0)
3. **Equation**: a = `0`, b = `0.1`, c = `0` (to convert tenths to m/s)
4. **Sensor type**: Wind Speed

### Reading via Modbus TCP Gateway

To read the same sensor through a Modbus TCP gateway at 192.168.4.2 (connected via the gateway's access point):

1. **MODBUS settings**: Enable, PORT = `TCP`, TCP Host = `192.168.4.2`, TCP Port = `502`
2. **Sensor slot**: Same as above — Port = `MODBUS_16`, Address = `1000`
3. The gateway translates TCP requests to RTU on its serial side.

## Troubleshooting

- **No readings (RTU)**: Verify the correct UART is enabled with matching baud rate (most Modbus devices use 9600 or 19200). Check wiring and termination resistors.
- **No readings (TCP)**: Ensure WiFi is connected and the TCP host is reachable. Verify the IP address and port.
- **Intermittent failures**: Check RS-485 wiring, termination resistors, and DE pin configuration.
- **Timeout**: Default timeout is 2 seconds. Slow devices or high-latency networks may need investigation.
- **Wrong values**: Double-check the register address, slave address, and byte order. Use the equation coefficients to scale raw values.
