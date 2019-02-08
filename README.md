# Keelson

A resilient durable execution engine that schedules fiber workflows, guarantees saga compensation across failures, and replays event histories from an append-only log.

## Overview

Keelson is an embedded workflow engine and distributed saga orchestrator. It executes deterministic workflows written in Wren on top of a lightweight, high-performance host runtime.

Workflows in Keelson are modeled as procedural, fiber-driven programs. Rather than relying on complex distributed transactions, Keelson guarantees resilience through event sourcing, deterministic fiber rehydration, and backward recovery using reverse-topological saga compensation.

## Features

- Deterministic Fiber Scheduler: Lightweight cooperative coroutines with suspend and resume semantics.
- Resilient Saga Orchestration: Automatic forward execution and reverse-topological backward compensation.
- Append-Only Event Sourcing: Crash-resilient write-ahead logging with strict sequencing and replay validation.
- Durable Timers and Signals: Monotonic timer wheels and asynchronous signal queues surviving execution restarts.
- Parallel Directed Graphs: Fan-out and fan-in join patterns (All, Any, Quorum) with cycle detection.
- Fault Tolerance Primitives: Adaptive retry policies with exponential backoff, circuit breakers, and rate limiters.
- Zero External Dependencies: Pure Wren kernel with embedded native support.

## Building and Running

Prerequisites:
- Wren CLI (`wren_cli`) or a standard C99 compiler (`clang` or `gcc`)
- `make` or `cmake`

Run the test suite:
```bash
make test
```

Execute an example workflow:
```bash
make run-example
```

## Architecture

```
+-------------------------------------------------------------+
|                       Keelson Engine                        |
|                                                             |
|   +-----------------------+     +-----------------------+   |
|   |   Workflow Fibers     |     |  Saga Compensation   |   |
|   +-----------------------+     +-----------------------+   |
|               |                             |               |
|               v                             v               |
|   +-----------------------------------------------------+   |
|   |             Fiber Scheduler & Replay Kernel         |   |
|   +-----------------------------------------------------+   |
|               |                             |               |
|               v                             v               |
|   +-----------------------+     +-----------------------+   |
|   |   Event History Log   |     |   Activity Registry   |   |
|   +-----------------------+     +-----------------------+   |
+-------------------------------------------------------------+
```

Detailed design notes and operational manuals are available in the `docs/` directory.
