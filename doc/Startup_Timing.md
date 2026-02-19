# Startup Timing Analysis

Boot to WiFi-responsive (pingable) takes approximately **7-25 seconds** depending on WiFi environment.

## Delay Breakdown

### 1. `setup()` — Splash/Boot Countdown: **3 seconds**

**Location:** `src/main.cpp` lines ~3315-3356

Three sequential `delay(1000)` calls provide a window for the user to press the BOOT button for factory reset. With OLED enabled, a countdown ("3 Sec", "2 Sec", "1 Sec") is displayed. Without OLED, the RGB LED cycles red/green/blue.

```cpp
// With OLED (lines 3315-3334):
delay(1000);  // "3 Sec"
delay(1000);  // "2 Sec"
delay(1000);  // "1 Sec"

// Without OLED (lines 3340-3344 or 3352-3356):
delay(1000);  // LED red
delay(1000);  // LED green
delay(1000);  // LED blue
```

After the countdown, `digitalRead(BOOT_PIN)` is checked — if LOW, factory reset is triggered.

**Note:** No tasks are created until after this completes, so WiFi cannot start during the countdown.

### 2. `wifiConnection()` — WiFi Off Delay: **~1 second**

**Location:** `src/main.cpp` lines 7714-7719

```cpp
WiFi.disconnect(true, true, 500);
WiFi.persistent(false);
WiFi.mode(WIFI_OFF);
delay(1000);
```

This disconnects and powers off WiFi before reconfiguring. On first boot WiFi was never connected, so the disconnect and 1-second wait are unnecessary overhead. On reconnect after a drop, the delay may help ensure clean radio state.

### 3. `wifiMulti.run(10000)` — WiFi Scan and Connect: **2-10 seconds**

**Location:** `src/main.cpp` line 7749

```cpp
if (wifiMulti.run(10000) == WL_CONNECTED)
```

The 10-second timeout allows `WiFiMulti` to scan for configured APs and connect. Actual time depends on:
- Number of APs in range
- Signal strength (affects scan time)
- Whether the target AP is found quickly

Typically 2-5 seconds with a strong, nearby AP.

### 4. `taskNetwork` Post-Connect: **~1 second**

**Location:** `src/main.cpp` lines ~8102-8219

After WiFi connects:
- `pingTimeout` set to `millis() + 10000` (not blocking, but delays first ping check)
- NTP time sync: `configTime()` + `vTaskDelay(1000)` + `getLocalTime(&tmstruct, 1000)`
- `webService()` called to start the HTTP/WebSocket servers

## Total

| Phase | Min | Max |
|-------|-----|-----|
| Splash countdown | 3s | 3s |
| WiFi off delay | 1s | 1s |
| WiFi scan/connect | 2s | 10s |
| Post-connect init | 1s | 2s |
| **Total** | **~7s** | **~16s** |

Worst case can reach ~25 seconds if WiFi scan takes the full 10-second timeout and NTP is slow to respond.

## Potential Optimizations (Not Implemented)

1. **Reduce splash countdown** — Check BOOT pin with shorter delays (e.g., 3x 300ms = 0.9s instead of 3s), or start WiFi in a task before the countdown ends.
2. **Skip WiFi-off delay on first boot** — Track whether WiFi was previously connected; skip `WiFi.mode(WIFI_OFF)` + `delay(1000)` on cold boot.
3. **Reduce `wifiMulti` timeout** — Lower from 10000ms to 5000ms if only one AP is configured.
4. **Start web server earlier** — Call `webService()` before WiFi STA connects (AP mode would already be up).
