# Keelson Architecture Specification

## 1. System Overview

Keelson is a high-performance, fault-tolerant durable execution engine. It schedules stateful fiber workflows, guarantees reverse-topological saga compensation across distributed failures, and enables deterministic time-travel replay from an append-only event journal.

The architecture decouples workflow business logic written in Wren from native systems concerns (binary serialization, Write-Ahead Logging, network multiplexing, and cryptographic checksums) implemented in C99.

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

## 2. Layered Architecture

### 2.1 Wren Workflow Layer (`src/wren/core/`)
The workflow layer contains the primary orchestrator and domain primitives:
- `KeelsonEngine`: Central coordinator binding event logs, storage engines, activity registries, fiber pools, and signal channels.
- `Saga`: Forward pipeline and backward compensation coordinator.
- `ReplayEngine`: Time-travel state reconstructor with side-effect caching and divergence detection.
- `FiberPool`: Cooperative coroutine scheduler with task priority queues and error boundary isolation.
- `DagOrchestrator`: Kahn topological sorter with barrier joins (`joinAll`, `joinAny`, `joinQuorum`).
- `TimerWheel`: Min-heap based monotonic time scheduler.
- `SignalChannel`: Thread-safe FIFO mailboxes for asynchronous external signaling.
- `QueryRegistry`: Read-only synchronous state inspection handlers.

### 2.2 Native C Host Layer (`src/c/`)
The native host layer provides low-level systems capabilities:
- `wren_vm.c`: Embeds the Wren virtual machine, handles module resolution, and injects foreign classes.
- `wal.c`: Append-only binary Write-Ahead Log with fsync durability and crash recovery scanners.
- `crc32.c`: Hardware-optimized IEEE 802.3 CRC32 calculation.
- `platform.c`: Monotonic clock access (`mach_absolute_time` on macOS, `clock_gettime` on Linux), memory RSS metrics, and atomic file replacement.
- `http_server.c`: Non-blocking POSIX HTTP/1.1 daemon with multiplexed select socket polling.
- `hash.c`: 64-bit FNV-1a hashing for payload verification and deduplication keys.

### 2.3 Storage and Persistence Layer (`src/wren/storage/`)
- `FileLogStorage`: Line-delimited JSON event log for human-readable auditability and streaming inspection.
- `MemoryLogStorage`: In-memory isolated storage for testing and ephemeral workloads.
- `SnapshotManager`: Periodic point-in-time workflow state serialization to bound replay recovery times.
- `LogCompactor`: Garbage collection and antecedent event truncation.

---

## 3. Workflow Execution Lifecycle

A workflow progresses through five deterministic phases:

```
  +--------------+
  |  1. DISPATCH |  Client sends workflow execution request
  +-------+------+
          |
          v
  +--------------+
  |  2. SCHEDULE |  FiberTask allocated and enqueued in PriorityQueue
  +-------+------+
          |
          v
  +--------------+
  |  3. EXECUTE  |  Fiber runs until activity invocation, timer, or signal
  +-------+------+
          |
     +----+----+
     |         |
     | Failure | Success
     v         v
+---------+  +-----------+
| 4. SAGA |  | 5. COMMIT |  Workflow state committed to append-only log
| ROLLBACK|  +-----------+
+---------+
```

1. **Dispatch:** Client submits a workflow definition and input payload via REST API or local runtime.
2. **Scheduling:** The engine assigns a monotonic sequence ID, initializes a deterministic state machine, and spawns a cooperative fiber in the `FiberPool`.
3. **Execution:** The fiber executes user business logic. When an activity is encountered, execution yields cooperatively while the activity handler executes within an isolated fault domain.
4. **Journaling:** Activity inputs, outputs, and side effects are appended to the immutable event log.
5. **Termination or Rollback:** Upon normal completion, state is marked `COMPLETED`. If an activity raises a fatal or non-retryable exception, the `Saga` orchestrator halts forward progress and executes registered compensation closures in reverse-topological order.

---

## 4. Cooperative Concurrency Model

Keelson utilizes cooperative fibers rather than preemptive kernel threads for workflow execution:
- **Zero Lock Contention:** Fiber execution within a single VM instance is non-preemptive. Workflows yield control explicitly at activity boundaries, durable timer waits, or signal checks.
- **Deterministic Scheduling:** Given identical inputs and event history, the fiber scheduler executes tasks in identical sequence.
- **Low Memory Overhead:** Each Wren fiber allocates a compact stack frame (under 4 KB initial overhead), allowing tens of thousands of concurrent workflow instances per gigabyte of memory.

---

## 5. Fault Isolation Boundaries

Failures are contained across four distinct boundaries:
1. **Activity Fault Isolation:** Uncaught exceptions inside an activity handler are caught by `ActivityRegistry` and wrapped in structured `ActivityError` instances rather than crashing the engine.
2. **Fiber Boundary:** If a fiber aborts unexpectedly, `FiberPool.step()` traps the runtime error, marks the task `FAILED`, and continues scheduling peer tasks.
3. **Storage Boundary:** Write errors to disk trigger immediate WAL fsync retries and circuit breaker activation to prevent log corruption.
4. **HTTP Host Boundary:** Malformed client requests or socket dropouts are handled gracefully by the non-blocking server without interrupting active fiber scheduling.
