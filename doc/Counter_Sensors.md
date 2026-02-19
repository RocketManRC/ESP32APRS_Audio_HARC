# Counter Input Sensors

## Overview

The firmware provides two pulse counter channels (COUNTER_0, COUNTER_1) and a simple logic level input. Implementation is in `src/sensor.cpp`. Counters use GPIO interrupts to count rising edges, making them suitable for tipping bucket rain gauges, anemometers, flow meters, and similar pulse-output sensors.

## Counter Channels

### COUNTER_0 (`PORT_CNT_0` = 5) and COUNTER_1 (`PORT_CNT_1` = 6)

**Initialization** (`sensorInit`, `sensor.cpp:1185-1192`):
- The GPIO from the sensor's `address` field is configured as `INPUT`
- A hardware interrupt is attached on **RISING edge**, calling `pulse_ch0()` or `pulse_ch1()`

**Counting** (`sensor.cpp:1150-1159`):
- Each rising edge increments a global counter (`cnt0` or `cnt1`)
- Counters are declared as `RTC_DATA_ATTR unsigned long` so they survive deep sleep

**Reading** (`getCNT0`/`getCNT1`, `sensor.cpp:330-370`):
- On each sample interval, the accumulated count is read and the counter is reset to 0
- Behavior depends on the sensor type:
  - **`SENSOR_RAIN` (11)**: Calls `sensorUpdateSum()` which accumulates the count additively over the averaging period. Designed for tipping bucket rain gauges where total rainfall matters.
  - **All other types**: Calls `sensorUpdate()` which treats the count as the current sample value (e.g., wind speed pulses per interval, flow meter ticks).

The `eqns[3]` coefficients (`a*v² + b*v + c`) are then applied to convert raw pulse counts into engineering units.

### LOGIC Input (`PORT_LOGIC` = 7)

Simpler than the counters — performs a `digitalRead()` on the GPIO specified in the `address` field and returns 0 or 1. No interrupt, no counting. Useful for on/off state detection (door switches, level sensors, etc.).

## Configuration

### Global Settings (`include/config.h`)

| Field | Type | Description |
|-------|------|-------------|
| `counter0_enable` | `bool` | Enable counter channel 0 |
| `counter0_active` | `bool` | Active level (used in web UI) |
| `counter0_gpio` | `int8_t` | GPIO pin, `-1` = disabled |
| `counter1_enable` | `bool` | Enable counter channel 1 |
| `counter1_active` | `bool` | Active level (used in web UI) |
| `counter1_gpio` | `int8_t` | GPIO pin, `-1` = disabled |

### Per-Sensor Slot (`SensorInfo` in `include/sensor.h`)

| Field | Type | Meaning for Counters |
|-------|------|----------------------|
| `enable` | `bool` | Enable this sensor slot |
| `port` | `uint8_t` | `PORT_CNT_0` (5), `PORT_CNT_1` (6), or `PORT_LOGIC` (7) |
| `address` | `uint16_t` | GPIO pin number for the interrupt input |
| `type` | `uint16_t` | `SENSOR_RAIN` (11) for cumulative sum mode; any other type for per-sample mode |
| `samplerate` | `uint16_t` | How often to read and reset the counter (seconds) |
| `averagerate` | `uint16_t` | Averaging window (seconds) |
| `eqns[3]` | `float[3]` | Equation coefficients: `a*v² + b*v + c` applied to raw count |
| `unit` | `char[10]` | Display unit string (e.g., "mm", "km/h") |
| `parm` | `char[15]` | Sensor name/label |

## AT Commands

Counter configuration can also be set via AT commands (`src/handleATCommand.cpp`):

| Command | Description |
|---------|-------------|
| `AT+COUNTER0_ENABLE=1/0` | Enable/disable counter 0 |
| `AT+COUNTER0_ACTIVE=1/0` | Set active level for counter 0 |
| `AT+COUNTER0_GPIO=<pin>` | Set GPIO pin for counter 0 |
| `AT+COUNTER1_ENABLE=1/0` | Enable/disable counter 1 |
| `AT+COUNTER1_ACTIVE=1/0` | Set active level for counter 1 |
| `AT+COUNTER1_GPIO=<pin>` | Set GPIO pin for counter 1 |

## Example: Tipping Bucket Rain Gauge

A tipping bucket rain gauge outputs one pulse per tip (e.g., 0.2794mm per tip):

- **Port**: `COUNTER_0`
- **Address**: GPIO pin connected to the gauge output
- **Type**: `SENSOR_RAIN` (enables cumulative sum mode)
- **Equation**: `a=0, b=0.2794, c=0` (converts tip count to mm)
- **Sample rate**: e.g., 60 seconds
- **Average rate**: e.g., 3600 seconds (1 hour total)

## Notes

- There is commented-out code in `main.cpp:3382-3388` for ESP32 hardware pulse counter (PCNT) that is not currently active. Counting is done purely via software interrupts.
- The `COUNTER0_RAW` and `COUNTER1_RAW` variables in `main.cpp:267-268` are also `RTC_DATA_ATTR` but appear unused in current code.
