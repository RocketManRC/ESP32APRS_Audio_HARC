# Wind Speed Sensor Interface

## Overview

The firmware supports wind speed (`SENSOR_WIND_SPD` = 9) and wind direction (`SENSOR_WIND_DIR` = 10) as sensor types. Wind data feeds into the APRS weather packet system. Wind speed is expected in **kph** internally; the firmware converts to mph (× 0.621) when formatting APRS weather packets (`weather.cpp:309`).

## Interfacing Options

### Option 1: Pulse-Output Anemometer (Counter Input)

Best for cup/vane anemometers with reed switch or hall effect output. Uses the GPIO interrupt-based counter to count rising edges per sample interval.

**Sensor slot configuration:**

| Field | Value |
|-------|-------|
| `port` | `COUNTER_0` (5) or `COUNTER_1` (6) |
| `type` | `SENSOR_WIND_SPD` (9) |
| `address` | GPIO pin connected to the anemometer signal |
| `samplerate` | Polling interval in seconds (e.g., 10) |
| `eqns[3]` | Calibration: `a=0, b=<factor>, c=0` to convert pulse count to kph |
| `unit` | "kph" |

**Calibration example:** If the anemometer outputs 1 pulse/sec per 2.4 kph and sample rate is 10 seconds, then a count of 10 pulses = 24 kph. Set `b=2.4` so the equation `0*v² + 2.4*v + 0` converts count to kph.

### Option 2: Modbus Anemometer

For sensors that provide wind speed over Modbus RTU (holding registers).

| Field | Value |
|-------|-------|
| `port` | `MODBUS_16Bit` (24) or `MODBUS_32Bit` (25) |
| `type` | `SENSOR_WIND_SPD` (9) |
| `address` | `(slave_addr × 1000) + register_addr` |
| `eqns[3]` | Convert raw register value to kph |

### Option 3: Analog Anemometer (ADC)

For sensors that output a voltage proportional to wind speed.

| Field | Value |
|-------|-------|
| `port` | `ADC` (2) |
| `type` | `SENSOR_WIND_SPD` (9) |
| `address` | ADC-capable GPIO pin |
| `eqns[3]` | Convert millivolt reading to kph |

## Wind Direction

Wind direction (`SENSOR_WIND_DIR` = 10) reports 0–360 degrees. Typically interfaced via:

- **ADC**: Resistor-network wind vane (e.g., Davis 6410) — use equation to convert millivolts to degrees
- **Modbus**: Digital wind vane with Modbus output — register value mapped to degrees

| Field | Value |
|-------|-------|
| `type` | `SENSOR_WIND_DIR` (10) |
| `eqns[3]` | Convert raw value to 0–360 degrees |

## Wind Gust Tracking

Wind gust is handled automatically by the weather system (`weather.cpp:216-225`). The firmware:

1. Reads the wind speed sensor slot mapped to `WX_WIND_GUST`
2. Stores samples in a rolling array (`wgArray[]`)
3. Reports the **maximum value** in the array as the gust

No separate gust sensor is needed — it derives the gust from wind speed samples.

## Linking Sensors to the Weather Report

Sensor slots are connected to the weather system through the web UI Weather configuration page. The relevant config fields are:

| Config Field | Purpose |
|--------------|---------|
| `wx_sensor_ch[]` | Maps each weather parameter (wind speed, direction, gust, etc.) to a sensor slot index |
| `wx_sensor_enable[]` | Enables/disables each weather parameter |
| `wx_sensor_avg[]` | Whether to use the averaged value or the latest sample |

The weather task (`weather.cpp:200-227`) reads these mappings via `getSensor()` to populate the `weather` struct, which is then formatted into an APRS weather packet.

**Weather parameters related to wind:**

| Flag | Bit | Description |
|------|-----|-------------|
| `WX_WIND_DIR` | bit 0 | Wind direction in degrees |
| `WX_WIND_SPD` | bit 1 | Wind speed (kph → converted to mph for APRS) |
| `WX_WIND_GUST` | bit 2 | Wind gust (max of recent speed samples) |

## Recommended Setup for a Standard Weather Station Anemometer

1. Wire the anemometer pulse output to a GPIO pin
2. Create a sensor slot: port=`COUNTER_0`, type=`SENSOR_WIND_SPD`, address=GPIO pin
3. Set the equation coefficients to convert pulse count per sample interval to kph
4. Wire the wind vane analog output to an ADC-capable GPIO
5. Create a sensor slot: port=`ADC`, type=`SENSOR_WIND_DIR`, address=GPIO pin
6. Set the equation to convert millivolts to degrees (0–360)
7. In the Weather config page, map `WX_WIND_SPD`, `WX_WIND_DIR`, and `WX_WIND_GUST` to the appropriate sensor slots
