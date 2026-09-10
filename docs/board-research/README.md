# Board Research

Reference documents and research notes for the Waveshare
**ESP32-C6-Touch-AMOLED-1.8** board. Numbered roughly in the order they were
written; group `00-…` files are broad overviews, `01-08` cover the board /
silicon / peripherals, and `10-18` are project-specific deep-dives that
graduated into reusable references.

For the canonical pin map, build commands, and "gotchas" that every project
needs to follow, see [`CLAUDE.md`](../../CLAUDE.md) at the repo root — that
file is the operational summary; the documents here are the long-form
research behind it.

## Overviews

| File | Description |
|---|---|
| [00 — Comprehensive Hardware Architecture](00-comprehensive-hardware-architecture.md) | Full subsystem analysis of the board (long form, ~45 KB) |
| [00 — Perplexity Overview](00-perplexity-overview.md) | First-pass research compilation when the board arrived |

## Board & Silicon

| # | Document | Description |
|---|---|---|
| 01 | [Official Docs](01-official-docs.md) | Waveshare wiki, product page, specs, pinout, demos, pricing |
| 02 | [ESP32-C6 Chip Reference](02-esp32-c6-chip-reference.md) | Espressif datasheet, WiFi 6, BLE 5, Thread/Zigbee, C6 vs S3 |
| 03 | [Community Projects](03-community-projects-and-resources.md) | GitHub repos, articles, comparable boards |
| 04 | [Display & Touch Drivers](04-display-touch-drivers.md) | SH8601 QSPI, FT3168 I2C, library support matrix |
| 05 | [Development Setup Guide](05-development-setup-guide.md) | Arduino, PlatformIO, ESP-IDF, MicroPython, ESPHome, LVGL |
| 06 | [Comparison with LCD-1.47](06-comparison-with-lcd147-project.md) | Side-by-side with [ws-esp32c6-lcd147-projects](https://github.com/chayuto/ws-esp32c6-lcd147-projects) |
| 07 | [Complete GPIO & IO Map](07-complete-gpio-and-io-map.md) | Every GPIO assignment, pin_config.h, free pin analysis |
| 08 | [I2C Bus & Peripherals](08-i2c-bus-and-peripherals.md) | All 6 I2C devices, power architecture, init sequence |
| 10 | [RTC & Audio Peripherals](10-rtc-audio-peripherals.md) | PCF85063 RTC, ES8311 audio codec, XiaoZhi AI |

## Project-Driven Research

| # | Document | Project | Description |
|---|---|---|---|
| 11 | [MCP Canvas Reference Architecture](11-mcp-canvas-reference-architecture.md) | 11 | LCD-1.47 MCP server + canvas drawing pipeline |
| 12 | [AMOLED MCP Canvas Strategy](12-amoled-mcp-canvas-strategy.md) | 11 | Canvas RAM strategy, option analysis, recommendation |
| 13 | [Implementation Plan](13-implementation-plan.md) | 11 | MCP canvas project architecture, module design, RAM budget |
| 14 | [Crying Detection Research](14-crying-detection-research.md) | 12, 13 | ML/DSP algorithms, ESP-SR/TFLite/Edge Impulse on C6, RAM budget |
| 15 | [Power Saving Strategies](15-power-saving-strategies.md) | all | WiFi off after NTP, display off, duty cycles, battery life estimates |
| 16 | [Toddler Product Research](16-toddler-product-research.md) | 14, 17 | Market scan of educational toys for the 1-3 yr range |
| 17 | [Toddler Project Ideas](17-toddler-project-ideas.md) | 14, 17 | Concept menu derived from #16, scored against board capabilities |
| 18 | [SD + Display SPI Sharing](18-sd-display-spi-sharing.md) | 16 | Why SD card and AMOLED display can't be on SPI2 simultaneously, with the runtime bus-switching workaround |

## Related

- [`docs/waveshare-support/`](../waveshare-support/) — verbatim Waveshare technical-support correspondence (referenced from #18)
- [`docs/research/`](../research/) — external research artefacts (BitChat protocol analyses for project 16)
- [`docs/reference/`](../reference/) — score sheets and other non-narrative reference data
