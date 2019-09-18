# Binary Write-Ahead Log (WAL) Specification

## 1. Specification Overview

The Keelson Write-Ahead Log (WAL) provides durable, append-only journal storage for workflow events and state transitions. Every state modification is committed and flushed to the binary WAL before being acknowledged to callers or applied to in-memory state.

The file format uses a fixed 32-byte binary header followed by a variable-length UTF-8 JSON payload. Integrity is verified per record using an IEEE 802.3 CRC32 checksum.

---

## 2. Binary Record Layout

All multi-byte integers are stored in **little-endian** byte order.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       Magic (0x4B45454C)                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    Version    |     Flags     |            Reserved           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                    Log Sequence Number (LSN)                  +
|                            (64-bit)                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                     Timestamp (nanoseconds)                   +
|                            (64-bit)                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Payload Length                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Payload CRC32 (IEEE)                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                     Variable Payload Data                     +
|                     (Payload Length bytes)                    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Field Definitions

| Byte Offset | Field Name | Type | Description |
|---|---|---|---|
| `0x00 - 0x03` | `magic` | `uint32_t` | Constant magic identifier `0x4B45454C` ("KEEL" in ASCII). |
| `0x04` | `version` | `uint8_t` | File format version. Currently `1`. |
| `0x05` | `flags` | `uint8_t` | Bit flags: `0x01` = Compressed, `0x02` = Checkpoint barrier. |
| `0x06 - 0x07` | `reserved` | `uint16_t` | Reserved for alignment and future extensions. Must be `0x0000`. |
| `0x08 - 0x0F` | `lsn` | `uint64_t` | Monotonically increasing Log Sequence Number starting at `1`. |
| `0x10 - 0x17` | `timestamp_ns` | `uint64_t` | Monotonic timestamp in nanoseconds since Unix epoch. |
| `0x18 - 0x1B` | `payload_len` | `uint32_t` | Size in bytes of the trailing payload data. |
| `0x1C - 0x1F` | `crc32` | `uint32_t` | IEEE 802.3 CRC32 checksum computed over the payload data. |
| `0x20 - ...` | `payload` | `uint8_t[]` | UTF-8 JSON event payload of length `payload_len`. |

---

## 3. Crash Recovery and Torn Write Truncation

During unexpected power outages or operating system crashes, a write operation may be interrupted mid-flight, producing a "torn write" (a partial header or corrupted payload at the end of the log).

Keelson recovers cleanly using the following protocol:
1. Open the WAL file and sequentially parse 32-byte headers.
2. For each record:
   - Validate that `magic == 0x4B45454C`.
   - Validate that the full payload of `payload_len` bytes is readable.
   - Recompute CRC32 over the payload and compare against header `crc32`.
   - Validate that `lsn` is strictly equal to `expected_lsn`.
3. If any check fails on the final record:
   - The engine identifies a torn write.
   - The file is truncated at the start of the invalid record using POSIX `ftruncate()`.
   - All preceding valid records are preserved, ensuring zero state corruption.

---

## 4. Fsync Policies and Durability Guarantees

Keelson supports two fsync modes:
- **Strict Synchronous (`sync_mode = 1`):** Every single record append invokes POSIX `fsync()` before returning. This guarantees zero Recovery Point Objective (RPO = 0) even across sudden power failure, suitable for financial ledger events.
- **Group Buffered (`sync_mode = 0`):** Appends are written to the kernel buffer cache and flushed periodically or at batch boundaries. This yields millions of writes per second while bounding potential data loss to the buffer flush window.
