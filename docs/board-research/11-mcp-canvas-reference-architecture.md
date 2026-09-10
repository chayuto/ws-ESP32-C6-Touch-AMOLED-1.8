# MCP Canvas Reference Architecture (LCD-1.47 Project 11)

Source: [ws-esp32c6-lcd147-projects](https://github.com/chayuto/ws-esp32c6-lcd147-projects) — `projects/11_mcp_server_display/`

## System Overview

```
AI Client (Claude / Python script)
    │ HTTP POST /mcp (JSON-RPC 2.0)
    ▼
ESP32-C6 HTTP Server (port 80, esp32-canvas.local)
    │
    ├── mcp_server.c — JSON-RPC router + 8 tool handlers
    │       │
    │       ▼ Non-blocking xQueueSend
    │
    ├── drawing_engine — FreeRTOS StaticQueue (depth 8)
    │       │
    │       ▼ Drained every 50 ms by LVGL timer
    │
    ├── ui_display — lv_canvas widget + render timer
    │       │           Canvas buffer: 172×320 RGB565 (110 KB BSS)
    │       │           Mutex: g_canvas_mutex (snapshot safety)
    │       ▼
    │
    └── LVGL flush → SPI2 DMA → ST7789 LCD panel
```

## Module Breakdown

### main.c (66 lines)

Startup sequence:

```
1. NVS init (required by Wi-Fi)
2. LCD_Init() — SPI2 bus + ST7789 panel + backlight LEDC
3. BK_Light(80) — 80% brightness
4. LVGL_Init() — draw buffers, display driver, tick timer
5. drawing_engine_init() — static queue
6. ui_display_init() — canvas widget + mutex
7. ui_display_show_connecting() — queue "Connecting..." screen
8. xTaskCreate(lvgl_task) — 16 KB stack, priority 1
9. wifi_init_sta() — blocks up to 30 s
10. ui_display_show_ip(ip) — update display
11. mcp_server_start() — mDNS + HTTP server
```

LVGL task pattern:
```c
static void lvgl_task(void *arg)
{
    lv_timer_create(ui_render_timer_cb, 50, NULL);  // 50 ms render timer
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10));
        lv_timer_handler();
    }
}
```

### drawing_engine.h/.c — Command Queue

Type-tagged union for draw commands:

```c
typedef enum {
    CMD_CLEAR, CMD_DRAW_RECT, CMD_DRAW_LINE,
    CMD_DRAW_ARC, CMD_DRAW_TEXT, CMD_DRAW_PATH,
} draw_cmd_type_t;

typedef struct {
    draw_cmd_type_t type;
    union {
        cmd_color_t clear_color;
        cmd_rect_t  rect;     // x, y, w, h, color, filled, radius
        cmd_line_t  line;     // x1, y1, x2, y2, color, width
        cmd_arc_t   arc;      // cx, cy, radius, start/end angle, color, width
        cmd_text_t  text;     // x, y, color, font_size, text[128]
        cmd_path_t  path;     // points[8], pt_cnt, closed, filled, color, width
    };
} draw_cmd_t;
```

Queue: 8-deep StaticQueue in BSS (no heap). Push functions are non-blocking `xQueueSend(..., 0)`.

Constants:
- `SCREEN_W = 172`, `SCREEN_H = 320`
- `DRAW_QUEUE_LEN = 8`
- `MAX_POLY_PTS = 8`
- `MAX_TEXT_LEN = 127`

### ui_display.h/.c — Canvas Layer

**Canvas buffer:** `lv_color_t g_canvas_buf[172 * 320]` — 110,080 bytes in BSS.

**Canvas mutex:** Binary semaphore protects buffer between render timer (writer) and snapshot encoder (reader).

**Init:**
```c
void ui_display_init(void) {
    g_canvas_mutex = xSemaphoreCreateMutex();
    lv_obj_t *scr = lv_obj_create(NULL);
    // Black background, no border, no padding
    s_canvas = lv_canvas_create(scr);
    lv_canvas_set_buffer(s_canvas, g_canvas_buf, SCREEN_W, SCREEN_H,
                         LV_IMG_CF_TRUE_COLOR);
    lv_canvas_fill_bg(s_canvas, lv_color_make(0,0,0), LV_OPA_COVER);
    lv_scr_load(scr);
}
```

**Render timer (50 ms):** Drains draw queue inside LVGL task context:
```c
void ui_render_timer_cb(lv_timer_t *timer) {
    while (xQueueReceive(g_draw_queue, &cmd, 0) == pdTRUE) {
        if (xSemaphoreTake(g_canvas_mutex, 20ms) != pdTRUE) {
            xQueueSendToFront(g_draw_queue, &cmd, 0);  // requeue
            break;  // try next tick
        }
        switch (cmd.type) {
            case CMD_CLEAR:     lv_canvas_fill_bg(...)
            case CMD_DRAW_RECT: lv_canvas_draw_rect(...)
            case CMD_DRAW_LINE: lv_canvas_draw_line(...)
            case CMD_DRAW_ARC:  lv_canvas_draw_arc(...)
            case CMD_DRAW_TEXT: lv_canvas_draw_text(...)
            case CMD_DRAW_PATH: lv_canvas_draw_line/polygon(...)
        }
        xSemaphoreGive(g_canvas_mutex);
    }
}
```

**Status screens:** `ui_display_show_connecting()` and `ui_display_show_ip()` push draw commands through the same queue — no direct LVGL calls.

### snapshot.h/.c — JPEG Encoding Pipeline

```
g_canvas_buf (172×320 RGB565)
    │ 2× downsample + RGB565→RGB888
    ▼
s_rgb888_buf (86×160 RGB888, 41 KB BSS)
    │ esp_new_jpeg encoder, quality 35, 4:4:4
    ▼
s_jpeg_out (20 KB BSS)
    │ mbedtls_base64_encode (heap-allocated output)
    ▼
Base64 string → JSON-RPC response
```

Canvas mutex held only during the downsample pass (not during JPEG encode).

Two APIs:
- `snapshot_encode()` — returns heap-allocated base64 string (caller frees)
- `snapshot_encode_raw()` — returns raw JPEG into caller-supplied buffer (used by `/snapshot.jpg`)

### mcp_server.h/.c — HTTP + MCP Protocol

**Wi-Fi STA:** Blocks up to 30 s. Disables modem sleep after connect (`esp_wifi_set_ps(WIFI_PS_NONE)`) — without this, each HTTP request adds 100-300 ms latency.

**mDNS:** `esp32-canvas.local`, `_http._tcp` service.

**HTTP endpoints:**
| Method | URI | Handler |
|--------|-----|---------|
| POST | `/mcp` | JSON-RPC 2.0 router |
| GET | `/ping` | Health check + queue depth |
| GET | `/snapshot.jpg` | Raw JPEG image |

**JSON-RPC methods:**
| Method | Handler |
|--------|---------|
| `initialize` | Returns server info + capabilities |
| `tools/list` | Returns cached tools JSON (built once at startup) |
| `tools/call` | Routes to tool handler by name |

**MCP Tools (8 total):**

| # | Tool | Required Params | Optional Params |
|---|------|-----------------|-----------------|
| 1 | `clear_canvas` | — | r, g, b (default 0) |
| 2 | `draw_rect` | x, y, w, h | r, g, b (255), filled (true), radius (0) |
| 3 | `draw_line` | x1, y1, x2, y2 | r, g, b (255), width (1) |
| 4 | `draw_arc` | cx, cy, radius, start_angle, end_angle | r, g, b (255), width (2) |
| 5 | `draw_text` | x, y, text | r, g, b (255), font_size (14 or 20) |
| 6 | `draw_path` | points[] (2-8 {x,y} objects) | closed (false), filled (false), r, g, b (255), width (1) |
| 7 | `get_canvas_info` | — | — |
| 8 | `get_canvas_snapshot` | — | — |

**Parameter validation:** `get_int()` helper validates type, range, required/optional with default. Error messages include param name and valid range.

**Tool response pattern:** All tools return immediately after pushing to queue. Drawing is async (50 ms later). Client calls `get_canvas_snapshot` to verify.

**Cached tools JSON:** `build_tools_json()` constructs the full `tools/list` response once at startup using cJSON, then stores the serialized string. Avoids re-serializing on every `tools/list` request.

## Shared Component: lcd_driver

**ST7789.h** — Pin definitions and constants:
```c
#define LCD_HOST         SPI2_HOST
#define EXAMPLE_LCD_H_RES  172
#define EXAMPLE_LCD_V_RES  320
#define Offset_X           34      // centering offset for 240-wide controller
#define Offset_Y           0
// SPI pins: SCLK=7, MOSI=6, MISO=-1, CS=14, DC=15, RST=21, BK=22
```

**LVGL_Driver.h** — Buffer and driver:
```c
#define LVGL_BUF_LEN  (EXAMPLE_LCD_H_RES * 20)   // 172×20 = 3440 pixels
#define EXAMPLE_LVGL_TICK_PERIOD_MS  2
```

Two static BSS buffers (buf1, buf2) for double-buffered partial refresh. DMA transfer via `esp_lcd_panel_draw_bitmap()` in flush callback.

## Build System

**CMakeLists.txt (project root):**
```cmake
cmake_minimum_required(VERSION 3.16)
set(EXTRA_COMPONENT_DIRS "../../shared/components")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(mcp_server_display)
```

**main/CMakeLists.txt — 5 source files, 14 dependencies:**
```cmake
idf_component_register(
    SRCS "main.c" "mcp_server.c" "drawing_engine.c" "ui_display.c" "snapshot.c"
    INCLUDE_DIRS "."
    REQUIRES lcd_driver nvs_flash esp_wifi esp_event esp_netif esp_timer
             esp_http_server json espressif__mdns mbedtls esp_system
             freertos driver espressif__esp_new_jpeg
)
```

**partitions.csv:** 2 MB app (8 MB flash):
```csv
nvs,        data, nvs,  0x9000,  0x6000,
factory,    0,    0,    0x10000, 2M,
flash_test, data, fat,  ,        528K,
```

**sdkconfig.defaults.template:**
```ini
CONFIG_IDF_TARGET="esp32c6"
CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_LV_FONT_MONTSERRAT_14=y
CONFIG_LV_FONT_MONTSERRAT_20=y
CONFIG_LV_MEM_SIZE_KILOBYTES=32
CONFIG_BT_ENABLED=n
CONFIG_FREERTOS_HZ=1000
CONFIG_FREERTOS_UNICORE=y
CONFIG_HTTPD_MAX_URI_LEN=512
CONFIG_HTTPD_MAX_REQ_HDR_LEN=512
CONFIG_ESP_TASK_WDT_TIMEOUT_S=15
```

## RAM Budget (LCD-1.47)

```
Canvas buffer (BSS):       110,080 B  (172×320×2)
LVGL draw buf ×2 (BSS):    13,760 B  (172×20×2 × 2)
LVGL heap pool:             32,768 B  (CONFIG_LV_MEM_SIZE_KILOBYTES=32)
Snapshot RGB888 (BSS):      41,280 B  (86×160×3)
Snapshot JPEG (BSS):        20,480 B
Snapshot HTTP (BSS):        20,480 B  (s_jpeg_http_buf in mcp_server.c)
Wi-Fi STA:                 ~55,000 B
FreeRTOS tasks:            ~25,000 B  (lvgl 16KB + httpd 8KB)
HTTP recv buffer:            2,048 B
Misc heap (cJSON, etc.):  ~10,000 B
────────────────────────────────────
Total:                     ~331 KB of 512 KB
Headroom:                  ~181 KB
```

## Key Design Patterns

1. **Static memory everywhere** — canvas, draw queue, snapshot buffers all in BSS. Zero heap fragmentation over long-running sessions.

2. **Async draw pipeline** — HTTP handler pushes to queue instantly, returns success. LVGL timer drains queue 50 ms later. Client uses `get_canvas_snapshot` to verify.

3. **Mutex-protected canvas** — Render timer holds mutex while drawing; snapshot holds mutex while reading. If snapshot is in progress, render requeues the command and retries next tick.

4. **Cached JSON schemas** — `tools/list` response built once at startup, stored as string. Eliminates per-request cJSON overhead.

5. **All LVGL mutations inside timer callbacks** — Never from HTTP handler task. Violation causes blank screen or corruption.

6. **Single file per concern** — 5 source files with clean boundaries: main (orchestration), mcp_server (protocol + WiFi), drawing_engine (queue), ui_display (canvas + render), snapshot (encode).
