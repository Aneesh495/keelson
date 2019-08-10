#!/usr/bin/env python3
"""
Keelson Binary WAL Inspector and Forensic Tool
Parses, validates, and decodes Keelson binary Write-Ahead Log files
with 32-byte headers and IEEE 802.3 CRC32 checksum verification.
"""

import argparse
import datetime
import os
import struct
import sys
import zlib
from typing import Optional

WAL_MAGIC = 0x4B45454C
HEADER_SIZE = 32
HEADER_FORMAT = "<IIQQII"


def inspect_wal(filepath: str, verbose: bool = False, json_only: bool = False) -> int:
    if not os.path.exists(filepath):
        print(f"Error: WAL file not found at '{filepath}'", file=sys.stderr)
        return 1

    file_size = os.path.getsize(filepath)
    if not json_only:
        print("=" * 65)
        print(f"   KEELSON BINARY WAL INSPECTOR: {os.path.basename(filepath)}")
        print("=" * 65)
        print(f"File Path: {filepath}")
        print(f"File Size: {file_size} bytes")
        print("-" * 65)

    offset = 0
    record_index = 0
    valid_count = 0
    corrupt_count = 0
    expected_lsn = 1

    with open(filepath, "rb") as f:
        while offset < file_size:
            header_bytes = f.read(HEADER_SIZE)
            if len(header_bytes) < HEADER_SIZE:
                if len(header_bytes) > 0:
                    print(f"Warning: Incomplete trailing header at offset {offset} ({len(header_bytes)} bytes)")
                break

            record_index += 1
            magic, ver_flags, lsn, timestamp_ns, payload_len, expected_crc = struct.unpack(
                HEADER_FORMAT, header_bytes
            )

            version = ver_flags & 0xFF
            flags = (ver_flags >> 8) & 0xFF

            if magic != WAL_MAGIC:
                print(f"[OFFSET {offset:08x}] CORRUPTED: Invalid magic {magic:#010x} (expected {WAL_MAGIC:#010x})")
                corrupt_count += 1
                break

            payload = f.read(payload_len)
            if len(payload) < payload_len:
                print(f"[OFFSET {offset:08x}] TRUNCATED: Expected {payload_len} bytes, read {len(payload)}")
                corrupt_count += 1
                break

            actual_crc = zlib.crc32(payload) & 0xFFFFFFFF
            crc_ok = (actual_crc == expected_crc)
            if not crc_ok:
                print(f"[OFFSET {offset:08x}] CRC MISMATCH: LSN {lsn}, expected {expected_crc:#010x}, got {actual_crc:#010x}")
                corrupt_count += 1
                break

            valid_count += 1
            ts_sec = timestamp_ns / 1_000_000_000.0
            dt_str = datetime.datetime.fromtimestamp(ts_sec, tz=datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

            payload_str = payload.decode("utf-8", errors="replace")

            if json_only:
                print(payload_str)
            else:
                seq_warn = " [OUT OF ORDER]" if lsn != expected_lsn else ""
                print(f"Record #{record_index:<4} | LSN: {lsn:<5}{seq_warn} | CRC: OK ({actual_crc:#010x}) | Len: {payload_len:<4} B | UTC: {dt_str}")
                if verbose:
                    print(f"  Header Details: Version={version}, Flags={flags:#04x}, Offset={offset:#010x}")
                    print(f"  Payload: {payload_str}")

            expected_lsn = lsn + 1
            offset += HEADER_SIZE + payload_len

    if not json_only:
        print("-" * 65)
        print(f"Summary: {valid_count} valid records, {corrupt_count} corruptions detected.")
        print("=" * 65)

    return 0 if corrupt_count == 0 else 1


def main():
    parser = argparse.ArgumentParser(description="Inspect and decode Keelson binary Write-Ahead Log files.")
    parser.add_argument("wal_path", help="Path to binary WAL file")
    parser.add_argument("-v", "--verbose", action="store_true", help="Print payload contents and header metadata")
    parser.add_argument("--json", action="store_true", help="Output only decoded JSON payload stream")

    args = parser.parse_args()
    sys.exit(inspect_wal(args.wal_path, verbose=args.verbose, json_only=args.json))


if __name__ == "__main__":
    main()
