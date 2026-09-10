# ws-ESP32-C6-Touch-AMOLED-1.8

A collection of ESP-IDF firmware projects for the **Waveshare ESP32-C6-Touch-AMOLED-1.8** development board.

Built with an **agentic-first development workflow** — each project is developed with [Claude Code](https://claude.ai/code) as the primary agent. Hardware specs, build rules, LVGL gotchas, and lessons learned across all projects live in [`CLAUDE.md`](CLAUDE.md) and `.claude/commands/`, giving the agent full context from the first message of every session.

---

## Board

| Feature | Detail |
|---|---|
| Chip | ESP32-C6, RISC-V 160MHz, single-core |
| Flash | 16MB external NOR-Flash |
| Display | 1.8" AMOLED, SH8601, 368x448, QSPI 40MHz |
| Touch | Capacitive, FT3168, I2C |
| PMIC | AXP2101 (LiPo charge/discharge, power rails) |
| IMU | QMI8658 (6-axis accelerometer + gyroscope) |
| RTC | PCF85063 (with backup battery pads) |
| Audio | ES8311 codec + dual microphone array + speaker |
| IO Expander | TCA9554 (controls display/touch power) |
| Wireless | Wi-Fi 6, BT 5 LE, IEEE 802.15.4 (Thread / Zigbee / Matter) |
| Storage | microSD card slot (SDMMC) |
| Battery | 3.7V LiPo, MX1.25 connector, ~350mAh |

---

## Projects

| # | Project | One-liner |
|---|---|---|
| 11 | [MCP Canvas](projects/11_mcp_canvas/) | MCP server — AI agent draws to AMOLED over WiFi (12 tools) |
| 12 | [Baby Cry DSP](projects/12_baby_cry_dsp/) | Crying detection via pure DSP — FFT, adaptive threshold, SD logging |
| 13 | [Baby Cry VAD](projects/13_baby_cry_vad/) | Crying detection with VAD gate + DSP (ESP-SR research documented) |
| 14 | [Sensory Play](projects/14_sensory_play/) | IMU-driven toy — particle physics, tilt gestures, touch keyboard |
| 15 | [Nursery Rhymes](projects/15_nursery_rhymes/) | Music-box player with realistic harmonic synthesis |
| 16 | [BitChat Relay](projects/16_bitchat_relay/) | BLE mesh relay for BitChat protocol — telemetry + SD logging |
| 17 | [PixelPet](projects/17_pixelpet/) | Tamagotchi-style virtual pet with sprite renderer + RTC decay |
| 18 | [Govee Monitor](projects/18_govee_monitor/) | BLE humidity/temperature monitor with charts, Supabase upload and a parquet archive |

Each project's own README has the detail (architecture, build steps, screenshots).
Numbering continues from an earlier board (ESP32-C6-LCD-1.47) in a separate repo,
which is why it starts at 11.

<p align="center">
  <img src="docs/media/mcp_canvas_demo.jpg" alt="MCP Canvas Demo" width="200">
</p>

---

## Getting Started

### Prerequisites

- [ESP-IDF v5.5+](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/get-started/)
- USB-C cable

### Build & Flash

```bash
# Activate ESP-IDF
. ~/esp/esp-idf/export.sh

# Build
idf.py -C projects/<name> build

# Flash
idf.py -C projects/<name> -p /dev/cu.usbmodem1101 flash
```

### New Project Setup

1. Copy the scaffold from an existing project or use `/new-project <name>` with Claude Code
2. Copy `sdkconfig.defaults.template` → `sdkconfig.defaults`, fill in WiFi credentials
3. Run `idf.py -C projects/<name> set-target esp32c6`
4. Build and flash

---

## Repository Structure

```
ws-ESP32-C6-Touch-AMOLED-1.8/
├── shared/components/      # Shared ESP-IDF components (amoled_driver, lvgl, ...)
├── projects/               # One subdirectory per firmware project (11_…, 12_…, …)
├── docs/
│   ├── board-research/     # Numbered research docs — board, silicon, peripherals
│   ├── waveshare-support/  # Verbatim vendor support correspondence
│   ├── research/           # External research artefacts (e.g. BitChat protocol)
│   ├── reference/          # Score sheets, lookup tables
│   ├── media/              # Photos and demo videos for READMEs
│   └── *.md                # Loose blog posts and ad-hoc setup notes
├── ref/                    # Vendor reference code (gitignored)
├── .claude/commands/       # Agent skills for Claude Code
├── CLAUDE.md               # Operational summary: pin map, build rules, gotchas
└── README.md               # You are here
```

## Documentation

- **[`CLAUDE.md`](CLAUDE.md)** — pin map, build commands, init sequence, every "gotcha" we've hit. Read this first.
- **[`docs/board-research/`](docs/board-research/)** — long-form research backing `CLAUDE.md`: official docs digest, chip reference, GPIO map, I2C bus, RTC/audio, power saving, project plans, etc. See its [index](docs/board-research/README.md).
- **[`docs/firmware-robustness.md`](docs/firmware-robustness.md)** — how this repo makes firmware-to-REST pipelines survive outages, reboots and its own bugs. Every rule traced to a real failure in project 18.
- **[`docs/waveshare-support/`](docs/waveshare-support/)** — exact vendor support tickets and replies, kept verbatim.
- **Per-project READMEs** — each `projects/<name>/README.md` covers that project's architecture and quirks.

## Critical Hardware Notes

1. **TCA9554 IO expander** (I2C 0x20) must set P4 and P5 HIGH before display/touch init
2. **SH8601 coordinates** must be even-aligned — LVGL needs a rounder callback
3. **No PSRAM** — display has built-in GRAM; use widget-based rendering, not framebuffer
4. **Nearly all GPIOs are used** by onboard peripherals — very few free pins for external hardware
5. **6 I2C devices** share one bus (GPIO 7/8): TCA9554, AXP2101, FT3168, QMI8658, PCF85063, ES8311
6. **AXP2101 PMIC** — long-press power button (2.5s) for hardware shutdown
7. **SD card and AMOLED display share SPI2** — cannot be active simultaneously. See [`docs/board-research/18-sd-display-spi-sharing.md`](docs/board-research/18-sd-display-spi-sharing.md).

## Key Links

- [Product Page](https://www.waveshare.com/esp32-c6-touch-amoled-1.8.htm)
- [Waveshare Docs Portal](https://docs.waveshare.com/ESP32-C6-Touch-AMOLED-1.8)
- [Official GitHub (Waveshare)](https://github.com/waveshareteam/ESP32-C6-Touch-AMOLED-1.8)
- [Schematic PDF](https://files.waveshare.com/wiki/ESP32-C6-Touch-AMOLED-1.8/ESP32-C6-Touch-AMOLED-1.8-Schematic.pdf)
- [ESP-IDF SH8601 Component](https://components.espressif.com/components/espressif/esp_lcd_sh8601)
- [ESP-IDF FT5x06 Touch Component](https://components.espressif.com/components/espressif/esp_lcd_touch_ft5x06)

## Sibling repos

Waveshare board workspaces built with the same agentic-first workflow. If a technique is
missing here, it is probably solved in one of the others.

| Repo | Board | Focus |
|---|---|---|
| [`ws-ESP32-C6-Touch-AMOLED-1.8`](https://github.com/chayuto/ws-ESP32-C6-Touch-AMOLED-1.8) **(this repo)** | ESP32-C6-Touch-AMOLED-1.8 — RISC-V C6, 1.8" SH8601 AMOLED, IMU, codec | MCP canvas, BitChat BLE relay, baby-cry DSP, sensory toys, Govee monitor |
| [`ws-ESP32-S3-Touch-AMOLED-1.8`](https://github.com/chayuto/ws-ESP32-S3-Touch-AMOLED-1.8) | ESP32-S3-Touch-AMOLED-1.8 — Xtensa S3 + PSRAM, 1.8" CO5300 AMOLED, CST820 touch | verified board notes, ESP-IDF template, ESP-SR voice picture book |
| [`ws-ESP32-S3-CAM`](https://github.com/chayuto/ws-ESP32-S3-CAM) | ESP32-S3-CAM-GC2145 — Xtensa S3 + 8 MB PSRAM, GC2145 DVP camera, ES8311/ES7210 audio | camera + audio bring-up, YAMNet baby-cry detection |
| [`ws-esp32c6-lcd147-projects`](https://github.com/chayuto/ws-esp32c6-lcd147-projects) | ESP32-C6 + 1.47" ST7789 LCD — RISC-V C6, 172×320 LCD, Wi-Fi 6 | LVGL animations, Wi-Fi 6 tools, MCP servers |
| [`ws-pico2go`](https://github.com/chayuto/ws-pico2go) | Pico2Go robot — RP2350A, TB6612 drive, TLC2543 line array, ST7789 | MicroPython robotics, PIO sensing, schematic reverse engineering |

## License

[MIT](LICENSE)
