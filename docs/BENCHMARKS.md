# Keelson Performance and Latency Benchmarks

This report documents the performance characteristics, throughput limits, and latency profiles of Keelson under synthetic workloads.

---

## 1. Test Environment and Methodology

- **Host Architecture:** Apple Silicon ARM64 (macOS 15.x) / Linux x86_64 POSIX
- **Compiler:** Clang 21.0.0 with `-std=c99 -Wall -Wextra -O2`
- **Wren VM:** Version 0.4.0
- **Measurement Tooling:** `tools/bench_throughput.py` and C monotonic timers (`mach_absolute_time` / `clock_gettime`)

Benchmarks measure non-preemptive cooperative scheduling, event append rates, query response times, and binary WAL serialization.

---

## 2. Executive Summary Metrics

| Benchmark Operation | Target Volume | Throughput | Avg Latency | p99 Latency |
|---|---|---|---|---|
| **Event Append (In-Memory Journal)** | 50,000 events | **2.72 M/sec** | **0.37 us** | 0.85 us |
| **Query Dispatch (Read-Only)** | 30,000 queries | **2.52 M/sec** | **0.40 us** | 0.92 us |
| **Workflow Dispatch & State Machine Init** | 20,000 workflows | **764.02 k/sec** | **1.31 us** | 2.45 us |
| **JSON Serde (Workflow History Objects)** | 25,000 objects | **74.01 MB/sec** | **3.99 us** | 7.20 us |
| **Binary WAL Append (Group Commit)** | 100,000 records | **1.85 M/sec** | **0.54 us** | 1.10 us |

---

## 3. Latency Percentile Distributions

Latency profile across 100,000 consecutive operations under sustained concurrency:

```
Latency (microseconds)
  5.0 |                                                  * (p99.9: 4.80 us)
  4.0 |
  3.0 |
  2.0 |                                     * (p99: 2.10 us)
  1.0 |                    * (p90: 0.72 us)
  0.4 |   * (p50: 0.35 us)
  0.0 +---+----------------+----------------+------------+
         p50              p90              p99          p99.9
```

- **p50 (Median):** 0.35 microseconds
- **p90:** 0.72 microseconds
- **p99:** 2.10 microseconds
- **p99.9:** 4.80 microseconds
- **Maximum Outlier:** 12.40 microseconds (caused by OS kernel memory page faults during heap growth)

---

## 4. Memory Footprint and Concurrency Scaling

Because Wren fibers allocate lightweight cooperative stack frames rather than multi-megabyte OS kernel thread stacks, memory scaling remains linear:

| Active Concurrent Fibers | Resident Set Size (RSS) | Memory per Fiber |
|---|---|---|
| **1,000** | 14.2 MB | 14.2 KB |
| **10,000** | 42.6 MB | 4.26 KB |
| **50,000** | 168.4 MB | 3.37 KB |
| **100,000** | 312.0 MB | 3.12 KB |

Even with 100,000 concurrent workflows suspended waiting for external signals or timers, memory consumption remains under 350 MB.

---

## 5. Architectural Performance Analysis

Three key design choices account for these throughput numbers:
1. **Zero Lock Contention:** Workflows execute on a single cooperative VM loop, eliminating mutex acquisitions, condition variables, and cache-line bouncing.
2. **Deterministic Priority Queue:** The binary min-heap uses contiguous arrays with cache-friendly indexing, achieving $O(\log N)$ task insertion with zero dynamic heap allocation per yield.
3. **Contiguous Binary WAL Headers:** 32-byte binary headers allow sequential recovery scanners to validate records without parsing arbitrary string formats or dynamic delimiters.
