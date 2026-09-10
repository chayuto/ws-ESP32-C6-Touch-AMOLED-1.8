# Comparison: ESP32-C6-Touch-AMOLED-1.8 vs ESP32-C6-LCD-1.47

## Reference Project
Comparable project: [ws-esp32c6-lcd147-projects](https://github.com/chayuto/ws-esp32c6-lcd147-projects)

## Board Differences

| Feature | LCD-1.47 (Current) | Touch-AMOLED-1.8 (New) |
|---|---|---|
| Display Type | IPS LCD | AMOLED |
| Display Size | 1.47" | 1.8" |
| Resolution | 172x320 | 368x448 (likely) |
| Display Controller | ST7789 (SPI2) | CO5300 or SH8601 (QSPI) |
| Touch | None | Capacitive touch (CST816T or similar) |
| Interface | SPI (12 MHz) | QSPI (higher bandwidth needed for AMOLED) |
| Color Depth | RGB565 16-bit | RGB565 16-bit (AMOLED supports deeper) |
| Backlight | PWM via LEDC (GPIO 22) | AMOLED self-emitting (no backlight needed) |
| Same MCU | ESP32-C6 RISC-V 160MHz | ESP32-C6 RISC-V 160MHz |
| WiFi | WiFi 6 (802.11ax) | WiFi 6 (802.11ax) |
| BLE | BLE 5.0 | BLE 5.0 |

## What Can Be Reused From lcd147 Project

### Directly Reusable (No Changes)
- **WiFi connection patterns** (`wifi_connect.c`) - same ESP32-C6 chip
- **NTP sync** (`ntp_sync.c`)
- **MCP server framework** (`mcp_server.c`, JSON-RPC 2.0 pattern)
- **App state machine pattern** (`app_state.h` with mutex protection)
- **LVGL threading model** - all mutations in LVGL task only
- **LED strip control** (`espressif__led_strip` component) - if board has WS2812
- **Partition table** (`partitions.csv` - 2MB app partition)
- **Build system structure** (CMake, shared components, EXTRA_COMPONENT_DIRS)
- **Agent skills** (`.claude/commands/`) - build, flash, hardware-specs concepts
- **sdkconfig patterns** - LVGL memory, font config, WiFi settings, BT disable

### Needs Adaptation
- **Display driver** - ST7789 SPI → AMOLED QSPI (completely different init sequence)
- **LVGL driver** - flush callback must use QSPI, different resolution, different draw buffers
- **Pin mappings** - different GPIO assignments for QSPI vs SPI
- **board_config.h** - new safe pins, reserved pins, ADC channels
- **LVGL buffer sizes** - larger resolution = larger buffers (368*20*2 = 14,720 bytes per buffer vs 3,440)
- **Display offset** - AMOLED likely different offset values
- **Backlight control** - AMOLED doesn't need PWM backlight, brightness via display command instead

### New Capabilities to Add
- **Touch input driver** - I2C touch controller (CST816T or similar)
  - LVGL input device registration (`lv_indev_drv_t`)
  - Touch interrupt handling (GPIO interrupt → I2C read)
  - Gesture support (swipe, long press, etc.)
- **QSPI display interface** - 4-wire SPI for higher bandwidth
- **AMOLED-specific features** - pixel-level dimming, true black, always-on display possible

## Architecture Pattern for New Board

Based on the lcd147 project structure, the AMOLED project should follow:

```
esp32c6-amoled-projects/
├── projects/
│   └── 01_first_project/
│       ├── CMakeLists.txt          # set(EXTRA_COMPONENT_DIRS "../../shared/components")
│       ├── partitions.csv          # 2MB app partition
│       ├── sdkconfig.defaults
│       └── main/
│           ├── CMakeLists.txt
│           ├── main.c
│           └── ...
├── shared/
│   └── components/
│       ├── amoled_driver/          # NEW: QSPI AMOLED init + LVGL driver
│       │   ├── amoled.h/.c        # QSPI bus, panel init, brightness
│       │   ├── LVGL_Driver.h/.c   # LVGL flush callback for QSPI
│       │   └── touch.h/.c         # I2C touch controller driver
│       ├── lvgl__lvgl/            # LVGL 8.3.11 or 9.x
│       └── espressif__led_strip/  # If board has RGB LED
├── CLAUDE.md                       # Board specs, build rules, gotchas
└── README.md
```

## Key Technical Considerations

### QSPI vs SPI for Display
- LCD-1.47 uses SPI2 at 12 MHz → ~1.5 MB/s throughput
- AMOLED-1.8 at 368x448 needs ~4x more data per frame
- QSPI (4 data lines) at ~40 MHz → ~20 MB/s, essential for smooth AMOLED
- ESP32-C6 has limited SPI peripherals - QSPI may need careful pin allocation

### Touch Integration with LVGL
```c
// Pattern from LVGL docs, adapted for this board:
static void touch_read_cb(lv_indev_drv_t *drv, lv_indev_data_t *data) {
    uint16_t x, y;
    bool touched = touch_read(&x, &y);  // I2C read from CST816T
    data->point.x = x;
    data->point.y = y;
    data->state = touched ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
}

// Register in LVGL_Init():
lv_indev_drv_t indev_drv;
lv_indev_drv_init(&indev_drv);
indev_drv.type = LV_INDEV_TYPE_POINTER;
indev_drv.read_cb = touch_read_cb;
lv_indev_drv_register(&indev_drv);
```

### Memory Budget (ESP32-C6)
- Total SRAM: ~512 KB
- LVGL heap: 64 KB (may need 96-128 KB for larger AMOLED resolution)
- Draw buffers: 2 x 14,720 bytes = ~29 KB (vs 6.8 KB on LCD-1.47)
- Touch buffer: minimal (~64 bytes)
- WiFi: ~80 KB when active
- FreeRTOS tasks: ~20 KB (4 tasks x 4-5 KB stack)
- Available for app: ~200 KB

### LVGL Configuration Changes
```ini
# Larger resolution
CONFIG_LV_HOR_RES_MAX=368
CONFIG_LV_VER_RES_MAX=448

# May need more memory
CONFIG_LV_MEM_SIZE_KILOBYTES=96

# Touch input
CONFIG_LV_USE_INDEV=y
```
