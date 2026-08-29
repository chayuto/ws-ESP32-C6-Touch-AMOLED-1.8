# CLAUDE.md — ESP32-C6-Touch-AMOLED-1.8

## Project Overview

Multi-project firmware repo for Waveshare ESP32-C6-Touch-AMOLED-1.8.
Each project lives in `projects/`. Shared ESP-IDF components live in `shared/components/`.
Research documents and board reference data live in the repo root as numbered markdown files.

## Repo Structure

```
ESP32-C6-Touch-AMOLED-1.8/
├── shared/components/    # Shared: amoled_driver, lvgl__lvgl, etc.
├── projects/             # One subdirectory per project
├── ref/                  # Vendor reference/test code — gitignored, do not modify
├── docs/
│   ├── internal/         # Private dev notes — gitignored
│   ├── household/        # Private household context — gitignored, see below
│   └── media/            # Board photos/videos for READMEs
├── 0x-*.md               # Research documents (board specs, driver info, etc.)
├── CLAUDE.md
└── .claude/commands/     # Agent skills: /build /flash /new-project etc.
```

## Board

- **Board:** Waveshare ESP32-C6-Touch-AMOLED-1.8
- **Chip:** ESP32-C6, RISC-V 160MHz, 16MB external flash
- **IDF Target:** `esp32c6` — ALWAYS set this, default is esp32 (Xtensa) which will fail
- **Display:** 1.8" AMOLED, SH8601, 368×448 portrait, QSPI 40MHz (SCLK=0, D0=1, D1=2, D2=3, D3=4, CS=5)
- **Touch:** FT3168 capacitive, I2C 0x38 (SDA=8, SCL=7, INT=15)
- **PMIC:** AXP2101, I2C 0x34 — manages all power rails, battery charge/discharge
- **IMU:** QMI8658, I2C 0x6B — 6-axis accelerometer + gyroscope, mounted 90° CCW on PCB back
- **RTC:** PCF85063, I2C 0x51 — with backup battery pads
- **Audio:** ES8311, I2C 0x18 (control) + I2S (MCK=19, BCK=20, WS=22, DI=21, DO=23)
- **IO Expander:** TCA9554/XCA9554, I2C 0x20 — P4=display power, P5=touch power
- **SD Card:** SPI-only on SPI2_HOST (CLK=11, CMD=10, DATA=18, CS=6) — NO native SDMMC host on C6
- **Button:** GPIO 9 (BOOT button) — pull-up, LOW when pressed
- **PWR Button:** via AXP2101 — power ON/OFF, configurable press actions
- **No RGB LED** on this board (unlike LCD-1.47 which has WS2812)
- **No backlight PWM** — AMOLED is self-emitting, brightness controlled via SH8601 register 0x51

## Pin Map (Complete)

| GPIO | Function | Notes |
|------|----------|-------|
| 0 | LCD SCLK | QSPI clock |
| 1 | LCD SDIO0 | QSPI data 0 |
| 2 | LCD SDIO1 | QSPI data 1 |
| 3 | LCD SDIO2 | QSPI data 2 |
| 4 | LCD SDIO3 | QSPI data 3 |
| 5 | LCD CS | QSPI chip select |
| 6 | SD CS | SD card chip select |
| 7 | I2C SCL | Shared: 6 devices |
| 8 | I2C SDA | Shared: 6 devices; **strapping pin** |
| 9 | BOOT | Button (pull-up); **strapping pin** |
| 10 | SD CMD | SDMMC command |
| 11 | SD CLK | SDMMC clock |
| 12 | USB D- | Native USB |
| 13 | USB D+ | Native USB |
| 15 | Touch INT | Active low; **strapping pin** |
| 16 | UART0 TX | Serial debug |
| 17 | UART0 RX | Serial debug |
| 18 | SD DATA | SDMMC data |
| 19 | I2S MCK | ES8311 master clock |
| 20 | I2S BCK | ES8311 bit clock |
| 21 | I2S DI | ES8311 mic data → ESP32 |
| 22 | I2S WS | ES8311 word select |
| 23 | I2S DO | ESP32 → ES8311 speaker |

**Almost no free GPIOs.** To get free pins, sacrifice SD card (6,10,11,18) or audio (19-23).

## I2C Bus (GPIO 7 SCL, GPIO 8 SDA, 200kHz)

| Device | Address | Function |
|--------|---------|----------|
| ES8311 | 0x18 | Audio codec control |
| TCA9554 | 0x20 | IO expander (display/touch power) |
| AXP2101 | 0x34 | Power management |
| FT3168 | 0x38 | Touch controller |
| PCF85063 | 0x51 | Real-time clock |
| QMI8658 | 0x6B | 6-axis IMU |

## ESP-IDF Environment

- **Version:** 5.5
- **Install:** `~/esp/esp-idf`
- **Activate:** `. ~/esp/esp-idf/export.sh`

## Build & Flash Commands

```zsh
# Activate IDF (required in every new shell)
. ~/esp/esp-idf/export.sh

# Build a project
idf.py -C projects/<name> build

# Flash
idf.py -C projects/<name> -p /dev/cu.usbmodem1101 flash

# Set target (one time only per project, wipes build dir)
idf.py -C projects/<name> set-target esp32c6

# Monitor serial output (use IDF venv python — idf.py monitor needs TTY)
~/.espressif/python_env/idf5.5_py3.14_env/bin/python -c "
import serial, time
ser = serial.Serial('/dev/cu.usbmodem3101', 115200, timeout=1)
ser.dtr=False; ser.rts=True; time.sleep(0.1); ser.rts=False; time.sleep(0.5)
start=time.time()
while time.time()-start<10:
    d=ser.read(ser.in_waiting or 1)
    if d: print(d.decode('utf-8',errors='replace'),end='')
ser.close()
"
```

**Serial monitor notes:**
- `idf.py monitor` does NOT work in non-TTY environments (Claude Code, scripts)
- System `python3` does NOT have pyserial — must use IDF venv python
- USB port varies: check `ls /dev/cu.usb*` first
- Use the agentic helper at `.claude/bin/agent_monitor.py` (proper DTR reset,
  line-buffered streaming, configurable capture window). See `/flash` skill.
- Every project's `sdkconfig.defaults` must include
  `CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y` — UART0 (GPIO 16/17) is not wired
  to the board's USB-C. Without this, app logs vanish silently.

## Each Project's CMakeLists.txt Must Include

```cmake
set(EXTRA_COMPONENT_DIRS "../../shared/components")
```

## Critical Initialization Order

This board requires specific power-up sequencing. Every project must follow this order:

```
1. I2C bus init (GPIO 7/8, 200kHz)
2. AXP2101 PMIC init (0x34) — configure power rails
3. TCA9554 IO Expander (0x20):
   - Set P4=OUTPUT, P5=OUTPUT
   - P4=LOW, P5=LOW → delay 200ms → P4=HIGH, P5=HIGH
   (This powers on display and touch controller)
4. SH8601 AMOLED init via QSPI
5. FT3168 touch init via I2C
6. Optional: QMI8658, PCF85063, ES8311, SD card
```

**If display is blank: check TCA9554 P4/P5 are HIGH.**

## Display (SH8601 QSPI AMOLED)

- **Resolution:** 368×448 portrait, RGB565
- **QSPI clock:** 40MHz on SPI2_HOST
- **Coordinate constraint:** x_start, y_start, x_end, y_end must be divisible by 2
  → LVGL needs a rounder callback to enforce this
- **Brightness:** Register 0x51 (0-255), not PWM. No backlight GPIO.
- **Init sequence:** Sleep Out (0x11) + 120ms → Tearing Effect → Display On (0x29) → Brightness
- **DMA buffers:** 1/4 screen double buffer = 2 × (368×112×2) = ~161 KB
- **ESP-IDF component:** `espressif/esp_lcd_sh8601` v2.0.1

## Touch (FT3168)

- **I2C address:** 0x38, compatible with FT5x06 family
- **Interrupt:** GPIO 15, active low
- **Multi-touch:** Up to 2 points
- **Gestures:** Swipe L/R/U/D, double-click
- **ESP-IDF component:** `espressif/esp_lcd_touch_ft5x06`
- **LVGL integration:** Register as `LV_INDEV_TYPE_POINTER` input device

## Partition Table

Default IDF partition = 1MB app. Too small for LVGL + AMOLED projects. Always use custom:
- 2MB app partition minimum (16MB flash allows up to 3MB+ if needed)
- Add to `sdkconfig.defaults`:
  ```
  CONFIG_PARTITION_TABLE_CUSTOM=y
  CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions.csv"
  CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y
  ```

## Credential Management (Public Repo)

`sdkconfig.defaults` is gitignored — never committed. Pattern:
- `sdkconfig.defaults` — real credentials, local only
- `sdkconfig.defaults.template` — placeholder values, committed to git
- README instructs: copy template → sdkconfig.defaults, fill in WiFi credentials

## Logging & Debuggability (Standing Rule)

Write every subsystem so its behaviour can be reconstructed from the serial
console alone. The board has no debugger attached in normal use and the display
shows only what the UI chooses to show — the console is the ground truth.

**Default to more logging, not less.** If you are deciding whether a line is
worth logging, log it.

- **Every module owns a `static const char *TAG`** and logs through `ESP_LOG*`,
  never `printf`.
- **Log every state transition** — init done, connected, disconnected, synced,
  paused, resumed, mode changed. A subsystem that changes state silently is
  undebuggable after the fact.
- **Log values, not adjectives.** `"WiFi down, retry in 8000 ms"` beats
  `"WiFi problem"`. Include the number, the address, the error code, the
  measured heap. Failures must carry `esp_err_to_name(err)` or the raw `rc`.
- **Never swallow an error.** Every non-OK return either propagates or gets a
  `ESP_LOGW`/`ESP_LOGE` line explaining what was lost as a result.
- **Emit a periodic one-line health heartbeat** from any long-running project
  (typically every 30–60 s) summarising the state a human would ask about:
  link status, clock source, queue depth, free heap, per-peer counts. Silence
  must never be the normal steady state.
- **Rate-limit, don't delete.** For per-sample events, log every sample at
  `ESP_LOGD` and a rolled-up count at `ESP_LOGI`, rather than dropping the
  information entirely.
- **Prefer `esp_console` commands** for anything a human would want to poke
  on demand (dump history, force a resync, show slots). A console command is
  cheaper than reflashing with extra printfs.
- Keep the log readable at 115200 baud: one line per event, TAG-prefixed,
  no multi-line banners in steady state.

Remember `.claude/bin/agent_monitor.py` is how an agent reads this output —
logs are the primary interface for verifying work on hardware, not an
afterthought.

## Critical Rules

- **Never build without setting target to esp32c6** — default esp32 builds fail with IRAM overflow
- **Delete `sdkconfig` when changing `sdkconfig.defaults`** — stale sdkconfig ignores new defaults
- **Delete `dependencies.lock` if moving/copying a project** — contains absolute paths
- **TCA9554 must be initialized before display/touch** — power rails controlled by IO expander
- **SH8601 coordinates must be even** — LVGL rounder callback required
- **No PSRAM** — full framebuffer doesn't fit, use partial draw buffers
- **I2S pin naming is confusing** — DI (GPIO 21) = ESP32 receives mic data, DO (GPIO 23) = ESP32 sends to speaker

## LVGL Gotchas (From LCD-1.47 Production, Still Apply)

- Use `lv_color_make(r, g, b)` — NOT `LV_COLOR_MAKE(r, g, b)` in function arguments.
  The macro is a compound literal that causes "expected expression" errors.
- All LVGL mutations must happen inside `lv_timer` callbacks, never from FreeRTOS tasks.
  Violation = blank screen or corruption. WiFi/sensor tasks set shared state; LVGL timer polls.
- `lv_spinner_create(parent, speed_ms, arc_degrees)` — 3 args.
- Arc 270° = 12 o'clock. Angles increase clockwise.
- Disable BT if not needed: `CONFIG_BT_ENABLED=n` saves ~50KB flash + ~30KB RAM.
- ESP32-C6 is single-core — use `xTaskCreate()`, never `xTaskCreatePinnedToCore()`.

## LVGL Touch Input Setup

```c
static void touch_read_cb(lv_indev_drv_t *drv, lv_indev_data_t *data) {
    esp_lcd_touch_handle_t tp = (esp_lcd_touch_handle_t)drv->user_data;
    esp_lcd_touch_read_data(tp);
    uint16_t x, y;
    uint16_t strength;
    uint8_t count = 0;
    esp_lcd_touch_get_coordinates(tp, &x, &y, &strength, &count, 1);
    if (count > 0) {
        data->point.x = x;
        data->point.y = y;
        data->state = LV_INDEV_STATE_PRESSED;
    } else {
        data->state = LV_INDEV_STATE_RELEASED;
    }
}
```

## Typical RAM Budget for LVGL + Wi-Fi + Touch Projects

```
LVGL draw buffer (×2):    164,864 B  (368×112×2 × 2 buffers, 1/4 screen)
LVGL heap pool:            65,536 B  (CONFIG_LV_MEM_SIZE_KILOBYTES=64)
Wi-Fi STA stack:           ~55,000 B
FreeRTOS tasks (typical):  ~40,000 B
HTTP server:                ~8,000 B
Misc heap (cJSON, etc.):   ~10,000 B
Touch driver:               ~1,000 B
---
Total:                     ~344 KB of 512 KB
Headroom:                  ~168 KB (tight — avoid large heap allocations)
```

## Gotchas Discovered in Projects 12/13 (Baby Cry Detection)

- **ES8311 I2C address**: `esp_codec_dev` expects 8-bit format (`0x30`), not 7-bit (`0x18`). The library does `device_address = addr >> 1` internally. Use `ES8311_CODEC_DEFAULT_ADDR` (0x30) from the header.
- **SH8601 brightness via QSPI**: Must encode command as `(0x02UL << 24) | (0x51 << 8)`. Raw `0x51` doesn't work — the QSPI interface needs the write-command opcode prefix. The `esp_lcd_sh8601` component's internal `tx_param()` does this automatically, but direct `esp_lcd_panel_io_tx_param()` calls bypass it.
- **ESP-SR VADNet on C6**: NOT available standalone. Bundled inside AFE pipeline (ESP32/S3/P4 only). WakeNet9s works on C6 (~10KB RAM, ~190KB flash) but only for wake words.
- **ESP-SR on C6 summary**: WakeNet9s (yes), VADNet via AFE (no), MultiNet (no)
- **TFLite Micro on C6**: Works via `espressif/esp-tflite-micro`. No SIMD, no FPU — use INT8 quantization. Confirmed by community ESP32-C6 keyword spotting project.
- **`esp_codec_dev` backward compat**: Check `CONFIG_CODEC_I2C_BACKWARD_COMPATIBLE` — if enabled, uses legacy I2C driver which conflicts with new `i2c_master` driver. Default is `n` (new driver) in recent versions.
- **GPIO 9 BOOT button**: Safe to use as user button after boot. Active LOW, external pull-up on board. Strapping pin — only matters during power-on.
- **Speaker amplifier**: NS4150B Class-D amp, enable via TCA9554 IO expander pin P7 (EXTO7).
- **QMI8658 axis mapping**: Chip is mounted 90° CCW on the PCB back. For portrait display: `screen_x = -chip_y`, `screen_y = chip_x`. Verified on hardware in project 14.
- **SD card shares SPI2 with display**: ESP32-C6 has no SDMMC host (only SDIO slave). SD card uses SDSPI on SPI2_HOST — same bus as the QSPI display. Cannot access both simultaneously. Use `amoled_release_spi()` / `amoled_reclaim_spi()` for runtime switching, or access SD before display init.

## Project 18 Telemetry Pipeline

`18_govee_monitor` uploads to Supabase and archives to Hugging Face:

```
board --3-min buckets--> Supabase (full history) --parquet--> HF dataset
        INSERT-only key                            /sync-data
```

- **Nothing prunes Supabase, until Supabase says so.** Retention is not
  enforced on a schedule; the trigger is the project actually hitting its
  storage limit. `--prune-days` defaults to 0 — do not schedule it and do not
  propose a retention policy before that. Growth is 343 B/row ≈ 640 kB/day ≈
  19 MB/month ≈ 229 MB/year, so a 500 MB free-tier database lasts ~2 years.
  When the limit does arrive: run `/sync-data`, confirm the archive covers the
  window, and only then prune it.
- **Row ids are deterministic UUIDv7** from (bucket ms, device id, sensor MAC).
  Every retry, replay and re-export is idempotent because of it. Changing the
  id inputs re-keys the entire archive — treat `uuid7.c` as frozen, and run
  `supabase/check_ids.sh` if you touch it.
- **The device inserts, never upserts.** PostgREST implements `on_conflict` as
  `INSERT .. ON CONFLICT`, which needs `SELECT` — and the publishable key is
  recoverable from the firmware image. A `409 / 23505` is success, not an error.
- **History is RAM-only, giving ~6 hours of offline tolerance.** This is an
  accepted limit, not pending work; do not propose NVS persistence again unless
  the deployment changes.
- **The Hugging Face archive is append-only.** Published parquet parts are
  never rewritten, merged or deleted. Part names hash their id set so a re-run
  is a no-op. Readers dedupe by id. Do not add compaction — merging means
  download/rewrite/upload, which can replace archived data with a subset.
- Credentials live only in `projects/18_govee_monitor/.env` (gitignored). The
  key in `sdkconfig.defaults` is the INSERT-only one and is deliberately
  powerless.

## Household Context (Project 18)

`docs/household/` holds the private, **gitignored** context that makes the
readings answerable: which room is which, what each one is like, and the
conclusions drawn so far. Read it before answering anything of the form "is this
reading bad" or "should I open a window" — the numbers alone cannot say, because
the answer depends on which room has no heater and who sleeps where.

- **Never commit it and never quote it outward.** This repo is public. Those are
  facts about someone's home, not about firmware. `/docs/household/` is in
  `.gitignore`; do not add exceptions or `git add -f`.
- `rooms.md` per-room notes, `sensors.md` which sensor is where, `findings.md`
  dated conclusions with their evidence.
- Every claim is tagged **measured / told / inferred / unknown**. Respect the
  tags: an `inferred` claim is challengeable, and the `unknown` list is the
  standing set of questions worth asking the human.
- **Reason in absolute humidity (g/m³), never RH.** RH is a ratio against
  temperature, so a cold room and cold outdoor air both read damp while holding
  less water. `tools/ventilation.sh` already does this correctly.

## Firmware Robustness (Standing Rules)

Full reasoning with the failures behind each rule:
[`docs/firmware-robustness.md`](docs/firmware-robustness.md). The short list:

- **Sort failures by reversibility.** A duplicate row is free; a lost or wrong
  row in an append-only archive is permanent. Spend complexity only there.
- **Derive row identity from the measurement**, so retries and replays are
  free. Never keep "have I sent this?" bookkeeping that can desync.
- **Verify backend semantics against the live backend.** "409 means already
  stored" was wrong and cost rows — a batch 409 aborts new rows too.
- **N independent streams need N cursors.** A shared watermark over per-sensor
  streams silently drops the sensors that missed the row budget.
- **Anything keyed by index must be reset when the index changes owner** —
  slot history, per-slot watermarks. Keep the list; the compiler cannot help.
- **Reset whole records, not the fields you were thinking about.** A partial
  reset left `n` set and re-emitted stale buckets as fresh `-327.68` readings.
- **Separate desired state from actual state and reconcile on a timer.**
  One-shot commands fail once and stay failed.
- **Lock anything wider than a word shared across tasks** — a torn 64-bit clock
  offset becomes a permanent wrong timestamp in the archive.
- **Check every metric can still move at the extreme it describes.** `backlog`
  reported batch size, so it saturated at 40 during exactly the outage it
  existed to measure.
- **Inject the clock** (`*_at()` entry points) so time-dependent logic is
  testable on the host, and **prove a regression test fails before it passes**.
- **Negative tests must fail for the right reason.** Assert the specific error;
  a 401 from the gateway and a 403 from Postgres mean very different things.
- **Degrade toward collecting data.** Display, upload and sync are recoverable
  later; a sample not taken is gone.

## Agent Skills

Use these slash commands for common operations:

| Command | Description |
|---|---|
| `/build <name>` | Activate IDF and build, with automatic failure recovery |
| `/flash <name>` | Auto-detect port and flash to connected board |
| `/new-project <name>` | Scaffold correct project structure with all known patterns |
| `/hardware-specs` | Full hardware reference: CPU, memory, accelerators, peripherals |
| `/display-ui` | LVGL UI reference for 368×448 AMOLED + touch |
| `/mcp-tool-design` | MCP tool design checklist |
| `/peripherals` | I2C peripheral reference: AXP2101, QMI8658, PCF85063, ES8311 |
| `/sync-data` | Sync project 18 readings from Supabase to Hugging Face |
