# Building a Dedicated BitChat Relay Node with ESP32-C6 and a Tiny AMOLED

*A weekend project that turned into a crash course in BLE stack sizes, SPI bus arbitration, and bloom filter tuning.*

---

I've been following [BitChat](https://bitchat.app) — a decentralized, encrypted messaging protocol that runs over BLE mesh. The idea is simple: phones talk to nearby phones, and messages hop peer-to-peer until they reach their destination. No servers, no internet required.

The problem? BLE range is limited, and mesh networks need relay nodes to extend coverage. Your phone can't relay messages when it's in your pocket with Bluetooth power-saving kicking in.

So I built a dedicated, always-on relay node. A small device that sits in a room, relays every BitChat packet it sees, and shows live mesh telemetry on a tiny AMOLED display.

## The Hardware

I used the **Waveshare ESP32-C6-Touch-AMOLED-1.8** — a compact dev board that packs a surprising amount into a small footprint:

- **ESP32-C6**: RISC-V single-core at 160MHz, BLE 5.0, 512KB SRAM
- **1.8" AMOLED**: 368x448 pixels, QSPI interface, vibrant colors even at low brightness
- **Capacitive touch**: FT3168 controller
- **PMIC**: AXP2101 with battery management — so it can run on a LiPo
- **SD card slot**: For exporting packet logs
- **16MB flash**: Plenty of room for firmware + SPIFFS logging partition

The board costs around $20, comes fully assembled, and runs on USB-C. For a relay that needs to sit somewhere and Just Work, it's ideal.

## Architecture

The firmware has a clear separation of concerns, all running on the single RISC-V core:

```
BLE Stack (NimBLE)
  |
  v
Packet Processing ──> Bloom Filter (dedup)
  |                      |
  v                      v
Relay to Peers      Telemetry Counters
  |                      |
  v                      v
Ring Buffer          LVGL Dashboard
(store & forward)    (500ms refresh)
  |
  v
SPIFFS Logger ──> SD Card Export
```

### Dual-Role BLE

The relay operates in both BLE roles simultaneously:

- **Peripheral**: Advertises the BitChat service UUID, accepts GATT writes from peers
- **Central**: Scans for other BitChat devices, connects, discovers their characteristic, subscribes to notifications

This means it can relay packets in both directions — from phones that connect to it, and from devices it connects to.

### Opaque Forwarding

Here's the key design decision: **the relay never decrypts anything**. BitChat uses Noise protocol encryption, and the relay has no keys. It only reads the outer unencrypted header (13+ bytes) to extract:

- TTL (decremented before forwarding)
- Message type (for telemetry)
- Sender ID (for peer tracking)
- Flags (broadcast vs. directed, signed, compressed)

Everything else is an opaque blob. The relay just moves bytes.

### Bloom Filter Deduplication

In a mesh network, the same packet arrives from multiple peers. Without dedup, you get exponential packet storms.

The relay uses an 8192-bit (1KB) bloom filter with 3 FNV-1a hash functions to track recently-seen packets. When a packet arrives:

1. Hash the full packet payload against the bloom filter
2. If all bits are set: **drop** (probably a duplicate)
3. If any bit is clear: **novel** — mark it, relay it

The bloom filter clears itself every 5 minutes (matching BitChat's packet TTL), which prevents false positive buildup. At the observed packet rates, the fill percentage stays well under 10%.

### The SPI Sharing Problem

This one was interesting. The ESP32-C6 has **only one user-accessible SPI peripheral** (SPI2_HOST). The QSPI AMOLED display uses it. The SD card also needs it.

They can't both use the bus at the same time. The solution is temporal multiplexing:

1. Pause LVGL rendering and wait for any in-flight DMA to complete
2. Turn off the display
3. Destroy the QSPI panel IO handle, free SPI2
4. Mount SD card on SPI2, copy SPIFFS logs, unmount, free SPI2
5. Recreate QSPI panel IO, turn display back on
6. Resume LVGL

The whole cycle takes about 500ms. The display goes dark briefly during SD export, which happens via long-press on the BOOT button or automatically every 30 minutes.

## The Dashboard

The AMOLED shows a live telemetry dashboard updated every 500ms:

- **Peer count and connection count** — how many BitChat devices are nearby
- **Packet rate** — rolling average of packets per second
- **Counters** — RX, TX, dropped (bloom duplicates), expired (TTL=0), buffered
- **Message type breakdown** — messages, acks, fragments, broadcasts, DMs, signed
- **TTL histogram** — 8 bars showing the distribution of packet hop counts
- **Peer list** — up to 8 peers with nickname, RSSI, and packet count
- **System status** — battery voltage/percentage, free heap, SD export count, bloom fill %

All LVGL mutations happen inside timer callbacks — never from the BLE task. The BLE task updates atomic counters; the LVGL timer polls them. This avoids the corruption bugs that plague most ESP32 + LVGL projects.

## First Test Results

I placed the relay on my desk with a phone running BitChat nearby. Here's what the serial console showed on first boot:

```
I (1419) main: After BLE: heap=183160 min=183160
I (1429) main: BitChat Relay running
I (1432) main: Free heap: 174392 bytes (min: 174256)
```

**174KB free heap** after BLE + LVGL + display + touch + SPIFFS are all initialized. That's comfortable — the ESP32-C6 has 512KB total, and we're using about 330KB.

Within 16 seconds of boot:

```
I (17596) ble_relay: BitChat peer found, RSSI=-82, addr=5b:dc:21:be:64:42
I (17596) ble_relay: Connecting to BitChat peer...
I (18225) ble_relay: Connection established, handle=0
I (18377) ble_relay: MTU updated: conn=0, mtu=256
I (18579) ble_relay: Found BitChat characteristic, val_handle=178
```

The relay found the phone, connected, negotiated MTU 256 (up from the default 23 bytes — critical for BitChat's larger packets), and discovered the GATT characteristic for packet exchange.

It also detected a second BitChat device in range:

```
I (19768) ble_relay: BitChat peer found, RSSI=-77, addr=76:3d:56:fb:56:56
```

Two peers at -77 to -83 dBm, stable connections, no packet loss. The relay was doing its job.

## The Stack Overflow Bug

The first firmware version crashed immediately on peer connection:

```
Guru Meditation Error: Core 0 panic'ed (Stack protection fault).
Detected in task "nimble_host" at 0x408101f6
```

The device rebooted, found the peer again, crashed again — an infinite crash loop that looked like "the screen keeps switching."

The root cause: NimBLE's host task defaults to **4096 bytes of stack**. But during connection + GATT service discovery, the call chain goes:

```
gap_event_handler()
  -> process_incoming_packet()
    -> uint8_t relay_buf[2048]  // on the stack!
```

A 2KB buffer on a 4KB stack, plus NimBLE's own frame overhead (~2KB for GATT operations). Classic stack overflow.

The fix was two-fold:

1. **Increase NimBLE host stack** to 6144 bytes (`CONFIG_BT_NIMBLE_HOST_TASK_STACK_SIZE=6144`)
2. **Make packet buffers static** instead of stack-allocated — safe because NimBLE's host task is single-threaded

Cost: 2KB more task stack + ~6KB in .bss for the static buffers. Cheap insurance.

## Memory Budget

Running the full stack on a chip with no PSRAM requires careful accounting:

| Component | RAM Usage |
|-----------|-----------|
| LVGL draw buffers (2x 33KB) | 66 KB |
| LVGL heap | 24 KB |
| NimBLE host + controller | ~120 KB |
| Ring buffer (32 x 2KB slots) | 64 KB |
| SPIFFS VFS cache | ~8 KB |
| FreeRTOS tasks + stacks | ~20 KB |
| Bloom filter | 1 KB |
| Telemetry + misc | ~10 KB |
| **Total** | **~313 KB** |
| **Free heap at runtime** | **~174 KB** |

No Wi-Fi (saves ~55KB), no Bluetooth Classic, no PSRAM needed.

## Data Pipeline

Packet metadata is logged to SPIFFS as CSV rows — one row per packet event (rx, relay, drop, expire) with uptime, peer ID, sender ID, RSSI, TTL, size, message type, and flags. A separate summary CSV captures periodic snapshots (every 5 minutes) with aggregate counters, heap usage, battery status, and bloom filter fill.

SPIFFS has 1MB allocated and gets cleared after each SD export. At typical packet rates, this is weeks of buffer. When an SD card is inserted and the user long-presses the BOOT button (or every 30 minutes automatically), the SPIFFS logs are appended to CSV files on the SD card.

The CSV format was chosen deliberately — it's trivially importable into pandas, Excel, or any data analysis tool. No proprietary format, no binary parsing needed.

## What's Next

This is project 16 in a series on this board. The relay works, but there's more to explore:

- **Multi-hop telemetry**: Track how many hops packets actually take before dying (the TTL histogram already hints at this)
- **Geographic deployment**: Place multiple relays in different rooms and measure mesh coverage
- **Power optimization**: The AXP2101 PMIC supports deep sleep — wake on BLE activity, sleep when no peers are nearby
- **Packet content analysis**: Even without decryption, traffic patterns (message frequency, burst patterns, peer churn) tell an interesting story about how people use mesh messaging

## Takeaways

1. **BLE dual-role on ESP32-C6 works well** — NimBLE handles simultaneous peripheral + central cleanly, and the ~120KB RAM cost is manageable if you skip Wi-Fi.

2. **Stack overflow is the #1 embedded BLE bug** — if your GATT callbacks allocate anything on the stack, you need more than the default 4KB. Use `static` buffers or heap allocation for anything over 256 bytes.

3. **Single-SPI sharing is annoying but solvable** — temporal multiplexing works; just be paranoid about DMA completion and state machine transitions.

4. **Bloom filters are perfect for mesh dedup** — 1KB of RAM eliminates packet storms. The false positive rate at typical fill levels is negligible.

5. **LVGL on AMOLED looks amazing** — even a simple text dashboard pops on an AMOLED. The SH8601 display at low brightness draws almost nothing, making it viable for battery-powered relay nodes.

---

*The full source code for this project (and 15 others on the same board) is at [ws-ESP32-C6-Touch-AMOLED-1.8](https://github.com/chayuto/ws-ESP32-C6-Touch-AMOLED-1.8) on GitHub.*
