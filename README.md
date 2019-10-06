# Keelson

A resilient durable execution engine that schedules fiber workflows, guarantees saga compensation across failures, and replays event histories from an append-only log.

[![Build](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/tests-81%2F81%20passing-brightgreen.svg)]()
[![Wren](https://img.shields.io/badge/language-Wren%200.4.0-blue.svg)]()
[![C99](https://img.shields.io/badge/host-C99-blue.svg)]()
[![Python](https://img.shields.io/badge/sdk-Python%203.9+-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()

---

## Overview

Keelson is an embedded durable execution engine and distributed saga orchestrator. It brings deterministic fault tolerance to procedural application code written in Wren, powered by an embedded native C99 runtime and Write-Ahead Log engine.

In distributed systems, multi-step business transactions frequently encounter transient network partitions, activity timeouts, host crashes, and semantic failures (such as payment rejections or quota exhaustions). Rather than requiring developers to coordinate complex Two-Phase Commit (2PC) transactions or manually write brittle ad-hoc error handlers, Keelson guarantees:

1. **Procedural Durability:** Write regular procedural code using cooperative fibers. If the process crashes mid-execution, Keelson recovers the exact execution state by replaying an immutable event sourcing log.
2. **Reverse-Topological Saga Rollback:** When unrecoverable business failures occur, Keelson halts forward execution and executes compensating actions in reverse topological order (LIFO), guaranteeing eventual consistency across services.
3. **Deterministic Replay & Side-Effect Caching:** During replay, previously executed activities are intercepted; cached results from history are returned immediately without re-invoking external network calls.
4. **Binary Write-Ahead Log (WAL):** Every state modification is committed to a binary WAL with 32-byte headers and IEEE 802.3 CRC32 checksums, protecting against torn writes and bit rot.
5. **Zero External Dependencies:** Built with pure Wren for the workflow engine and standard POSIX C99 for the native host, achieving microsecond-level dispatch latency without heavy runtime overhead.

---

## Architectural Blueprint

```
+-----------------------------------------------------------------------+
|                           Client Applications                         |
|             (Python SDK / HTTP REST Clients / Web Dashboard)          |
+-----------------------------------------------------------------------+
                                   | HTTP/1.1 REST
                                   v
+-----------------------------------------------------------------------+
|                    Keelson Native C Host Engine                       |
|  +--------------------+  +--------------------+  +-----------------+  |
|  | POSIX HTTP Server  |  | Binary WAL Engine  |  | CRC32 & Hashing |  |
|  | (select/non-block) |  | (32-byte header)   |  | (IEEE 802.3)    |  |
|  +--------------------+  +--------------------+  +-----------------+  |
|                                  |                                    |
|                      Wren VM Embedding Boundary                       |
|                                  v                                    |
|  +-----------------------------------------------------------------+  |
|  |                     Wren Core Execution Engine                  |  |
|  |  +--------------------+  +-------------------+  +------------+  |  |
|  |  | Cooperative Fiber  |  | Min-Heap Priority |  | FSM State  |  |  |
|  |  | Scheduler Pool     |  | Event Queue       |  | Machine    |  |  |
|  |  +--------------------+  +-------------------+  +------------+  |  |
|  |  +--------------------+  +-------------------+  +------------+  |  |
|  |  | Distributed Saga   |  | Event Sourcing    |  | DAG Join   |  |  |
|  |  | Orchestrator       |  | Replay Engine     |  | Barriers   |  |  |
|  |  +--------------------+  +-------------------+  +------------+  |  |
|  |  +--------------------+  +-------------------+  +------------+  |  |
|  |  | Durable TimerWheel |  | Signal Mailboxes  |  | Prometheus |  |  |
|  |  | & Cron Parser      |  | & Query Registry  |  | Exporter   |  |  |
|  |  +--------------------+  +-------------------+  +------------+  |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
|                           Storage Layer                               |
|        [Binary WAL Files]    [JSON History Logs]    [Snapshots]       |
+-----------------------------------------------------------------------+
```

---

## Core Capabilities

### 1. Cooperative Fiber Scheduler
- Non-preemptive coroutine scheduling using Wren fibers.
- Priority scheduling via binary min-heap (`PriorityQueue`): critical compensation tasks and signals take precedence over routine forward tasks.
- Cooperative yields (`Fiber.yield` / `fiber.call`) maintain execution stack frames across activity boundaries.
- Error isolation prevents unhandled task exceptions from unwinding the host VM loop.

### 2. Distributed Saga Orchestrator
- Forward execution pipeline accumulates step outputs and passes context to downstream steps.
- Backward recovery executes semantic undo handlers in exact reverse order (LIFO) upon fatal errors.
- Hierarchical nested sagas: sub-sagas execute and compensate within local scopes before propagating failures to parent sagas.
- Robust compensation error tracking: records failed compensations while continuing to rollback antecedent steps.

### 3. Event Sourcing and Replay Engine
- State is modeled as an immutable left-fold over historical events.
- Intercepts activity calls during replay, returning cached results without executing duplicate external side effects.
- Non-determinism detection (`ReplayDivergenceError`) aborts replay if modified workflow code diverges from recorded history.
- Snapshotting and log compaction bound recovery times from $O(N)$ to $O(1)$.

### 4. Binary Write-Ahead Log
- Structured 32-byte binary header with magic bytes `0x4B45454C`, versioning, 64-bit monotonic LSN, and nanosecond timestamps.
- IEEE 802.3 CRC32 checksum computed per record.
- Automatic torn write detection and safe file truncation during recovery scanning.
- Configurable fsync modes: per-record synchronous flushing for strict durability or group commit for high throughput.

### 5. Resilient Distributed Primitives
- **DAG Orchestrator:** Kahn topological sorting with cycle detection and join barriers (`joinAll`, `joinAny`, `joinQuorum`).
- **Durable TimerWheel:** Chronologically ordered monotonic timers surviving worker restarts.
- **Signal Channels:** Bounded FIFO mailboxes for asynchronous external event delivery.
- **Query Registry:** Synchronous read-only state inspection without triggering side effects.
- **Circuit Breakers & Rate Limiters:** Tri-state circuit breakers (`CLOSED`, `OPEN`, `HALF_OPEN`) and token/leaky bucket rate limiting.
- **Idempotency Deduplication:** 64-bit FNV-1a payload hashing with TTL expiration.
- **Cron Parser:** Standard 5-field cron expression parser supporting wildcards, ranges, and intervals.
- **Telemetry:** Prometheus metrics exporter tracking counters, gauges, and latency histograms.

---

## Quickstart

### Prerequisites
- Clang or GCC compiler with C99 support (`clang -std=c99` or `gcc -std=c99`)
- Wren VM development headers / `libwren` (available via Homebrew or standard package managers)
- Python 3.9+ (for SDK and benchmarking tools)
- GNU Make

### Building the Native Host
```bash
make build
```
This produces the native binary executable at `./bin/keelson`.

### Running All Test Suites
Execute both the 81-test Wren engine suite and the Python SDK test suite:
```bash
make test
```

### Running Production Workflow Demonstrations
```bash
# 1. E-Commerce Order Saga (multi-step checkout with automated fraud rollback)
./bin/keelson run examples/e_commerce_order_saga.wren

# 2. Distributed ETL Data Pipeline (staged extraction with rollback on schema error)
./bin/keelson run examples/distributed_etl.wren

# 3. IoT Fleet Firmware Rollout (staged canary gates with automated rollback)
./bin/keelson run examples/iot_fleet_rollout.wren

# 4. Human-in-the-Loop Approval (asynchronous signal handling with VP escalation)
./bin/keelson run examples/human_approval.wren
```

### Starting the HTTP Daemon
```bash
./bin/keelson serve --port 8080
```

Verify daemon health:
```bash
curl -s http://127.0.0.1:8080/health
# {"status":"ok","version":"1.0.0"}

curl -s http://127.0.0.1:8080/metrics
# # HELP keelson_workflows_active Total currently executing fibers
# # TYPE keelson_workflows_active gauge
# keelson_workflows_active 12
```

---

## Interactive Web Dashboard

Keelson includes a responsive, dark-mode single-page execution dashboard located in `web/`:

```bash
open web/index.html
```

Features:
- **Visual Saga Pipeline:** Live rendering of forward pipeline steps and reverse compensation branches.
- **Event Sourcing Journal:** Monotonic table of historical events with sequence numbers, UTC timestamps, and JSON payloads.
- **Deterministic Time-Travel Slider:** Step through historical events one by one to inspect reconstructed point-in-time state.
- **Prometheus Telemetry View:** Real-time visibility into fiber scheduling latency and throughput.

---

## Operational Tools and Chaos Engineering

### Chaos Monkey Resilience Verification
Simulates process crashes (`SIGKILL`), transient network partitions, non-deterministic replay divergence, and binary WAL bit-rot:
```bash
./tools/chaos_monkey.py
```

### Performance and Latency Benchmarks
Measures workflow dispatch throughput, event append latency, and JSON serialization rates:
```bash
./tools/bench_throughput.py
```

### Binary WAL Inspector
Decodes binary Write-Ahead Log files, validates CRC32 checksums, and inspects event payloads:
```bash
./tools/wal_inspector.py data/wal/keelson_wal.bin -v
```

### Distributed Trace Generator
Converts Keelson event logs into Jaeger / OpenTelemetry compatible JSON traces:
```bash
./tools/generate_trace.py workflow_events.json -o trace.json
```

---

## Performance Profile

Benchmarked on Apple Silicon ARM64 with Clang `-O2`:

| Operation | Throughput | Average Latency |
|---|---|---|
| **Event Append (Memory Journal)** | **2.72 M / sec** | **0.37 us** |
| **Query Dispatch (Read-Only)** | **2.52 M / sec** | **0.40 us** |
| **Workflow Dispatch & FSM Init** | **764 k / sec** | **1.31 us** |
| **JSON Serde Throughput** | **74.01 MB / sec** | **3.99 us** |
| **Binary WAL Group Commit** | **1.85 M / sec** | **0.54 us** |

Memory footprint scales at under 4.5 KB per suspended workflow fiber, allowing 50,000 concurrent workflows in under 170 MB of RAM.

---

## Technical Documentation

Deep-dive architectural specifications are available in the `docs/` directory:

- [Architecture & Layering Specification](docs/ARCHITECTURE.md): VM embedding, memory model, and fault domains.
- [Distributed Saga Pattern & Compensation](docs/SAGA_PATTERN.md): LIFO semantic rollback, idempotency, and nested sagas.
- [Deterministic Replay & Crash Recovery](docs/REPLAY_ENGINE.md): Side-effect caching and non-determinism guards.
- [Binary WAL Specification](docs/WAL_SPECIFICATION.md): 32-byte header format, CRC32 checks, and torn write recovery.
- [Fiber Scheduler & Priority Queuing](docs/FIBER_SCHEDULER.md): Cooperative coroutines, binary min-heap, and backpressure.
- [Complete API Reference](docs/API_REFERENCE.md): Full Wren and Python SDK method reference.
- [Performance & Benchmark Report](docs/BENCHMARKS.md): Latency percentiles, scaling limits, and methodology.

---

## Repository Structure

```
keelson/
├── bin/                          # Compiled native binaries (keelson)
├── docs/                         # Technical specifications and guides
│   ├── ARCHITECTURE.md           # System architecture and concurrency
│   ├── SAGA_PATTERN.md           # Distributed sagas and compensation
│   ├── REPLAY_ENGINE.md          # Deterministic replay and time travel
│   ├── WAL_SPECIFICATION.md      # Binary WAL framing and recovery
│   ├── FIBER_SCHEDULER.md        # Min-heap priority fiber pool
│   ├── API_REFERENCE.md          # Complete Wren & Python API reference
│   └── BENCHMARKS.md             # Throughput and latency benchmarks
├── examples/                     # Runnable production workflow examples
│   ├── e_commerce_order_saga.wren
│   ├── distributed_etl.wren
│   ├── iot_fleet_rollout.wren
│   └── human_approval.wren
├── sdk/                          # Client SDKs
│   └── python/                   # Python client library
│       ├── keelson/              # Client, models, and exceptions
│       ├── tests/                # SDK unit test suite
│       └── pyproject.toml        # Package build configuration
├── src/
│   ├── c/                        # Native C host engine (C99)
│   │   ├── include/              # Header files (crc32, wal, platform, etc.)
│   │   ├── crc32.c               # IEEE 802.3 CRC32 calculation
│   │   ├── hash.c                # 64-bit FNV-1a hashing
│   │   ├── http_server.c         # Non-blocking POSIX HTTP/1.1 daemon
│   │   ├── platform.c            # Monotonic timing and atomic I/O
│   │   ├── wal.c                 # Binary Write-Ahead Log engine
│   │   ├── wren_vm.c             # Wren VM host embedding
│   │   └── main.c                # CLI entrypoint
│   └── wren/                     # Core Wren execution engine
│       ├── core/                 # Engine primitives (saga, replay, pool, etc.)
│       ├── storage/              # Storage backends (file, memory, compactor)
│       ├── runtime/              # Unified KeelsonEngine coordinator
│       ├── workflows/            # Production workflow implementations
│       └── keelson.wren          # Engine facade module
├── test/                         # Test suites
│   ├── unit/                     # Unit test suites (20+ suites)
│   ├── integration/              # End-to-end integration test suites
│   ├── test_framework.wren       # Pure Wren test framework
│   └── test_runner.wren          # Test runner entrypoint
├── tools/                        # Operational and diagnostic tooling
│   ├── bench_throughput.py       # Micro-benchmark throughput suite
│   ├── chaos_monkey.py           # Chaos engineering and failure injection
│   ├── generate_trace.py         # OpenTelemetry / Jaeger trace generator
│   ├── lint_em_dashes.sh         # Prohibited em dash verification script
│   └── wal_inspector.py          # Binary WAL parser and hex dumper
├── web/                          # Interactive execution dashboard
│   ├── index.html                # Responsive dashboard markup
│   ├── style.css                 # Dark-mode developer theme
│   └── app.js                    # Reactive DAG visualizer and replay UI
├── Makefile                      # Build automation and test orchestration
├── LICENSE                       # MIT License
└── README.md                     # Project documentation
```

---

## Verification and Quality Guarantees

Every commit and pull request must satisfy four strict verification gates:
1. **Zero Em Dashes:** The repository enforces a strict policy forbidding em dashes in code, comments, documentation, and commit messages (enforced via `tools/lint_em_dashes.sh`).
2. **Deterministic Replay Guarantee:** Workflow state must be 100% reconstructible from event history without invoking live activities.
3. **Saga Consistency Guarantee:** In the event of an activity fault, all preceding completed actions must be compensated in reverse topological order.
4. **Clean Test Pass:** All 81 core engine tests and SDK tests must pass with zero warnings or failures (`make test`).
