# Cooperative Fiber Scheduler and Priority Queuing

## 1. Concurrency Model and Primitives

Keelson schedules concurrent workflows using cooperative coroutines (fibers) rather than preemptive operating system threads. Fibers execute on a single native thread within the Wren virtual machine, eliminating data races, deadlocks, and lock contention overhead.

### 1.1 Wren Fiber Semantics
- **Spawning:** `Fiber.new { ... }` creates a suspended fiber with an isolated call stack.
- **Yielding:** `Fiber.yield(value)` suspends the active fiber, pauses its stack frame, and yields control back to the scheduler, optionally transmitting a yielded value.
- **Resumption:** `fiber.call(arg)` or `fiber.try(arg)` resumes execution from the exact yield point, injecting `arg` as the return value of `Fiber.yield()`.
- **Fault Trapping:** `fiber.try()` catches runtime aborts cleanly. If the fiber crashes, `fiber.try()` returns `null` and populates `fiber.error` without unwinding the host thread stack.

---

## 2. Min-Heap Priority Queue Scheduling

The `FiberPool` manages runnable tasks using a binary min-heap (`PriorityQueue`):

```
                     [Priority 1: Compensation Task]
                               /         \
                              /           \
      [Priority 5: Urgent Activity]     [Priority 10: Standard Workflow]
               /           \
              /             \
[Priority 10: Batch Task]  [Priority 20: Telemetry Scrub]
```

### Algorithmic Complexity

| Operation | Time Complexity | Description |
|---|---|---|
| `push(element, priority)` | $O(\log N)$ | Inserts task at leaf and sifts up maintaining min-heap invariant. |
| `pop()` | $O(\log N)$ | Extracts root (lowest numerical priority value) and sifts down. |
| `peek()` | $O(1)$ | Inspects the next highest-priority task without dequeuing. |
| `clear()` | $O(1)$ | Discards all elements and resets heap pointer. |

### Priority Tiers

Keelson assigns priorities based on operational urgency:
- **Priority 1 (Emergency):** Saga reverse compensation steps and panic rollbacks.
- **Priority 5 (High):** Human-in-the-loop signal resumption and timeout timers.
- **Priority 10 (Normal):** Forward workflow activities and standard business logic.
- **Priority 20 (Low):** History log compaction, snapshot creation, and background telemetry.

---

## 3. Fiber Task Lifecycle State Machine

Each task in the scheduler progresses through five distinct lifecycle states:

```
  [CREATED]
      |
      v
   [READY] <----------------+
      |                     |
      | Scheduler pop()     | resume()
      v                     |
  [RUNNING] ----------------+ (cooperative yield)
      |         yield()
      +------------+------------+
      |            |            |
      v            v            v
 [COMPLETED]    [FAILED]   [CANCELLED]
```

- **CREATED:** Task allocated with user closure, priority, and unique task ID.
- **READY:** Placed into min-heap waiting for an execution slice.
- **RUNNING:** Currently being evaluated by `fiber.try()`.
- **SUSPENDED:** Voluntarily yielded waiting for external I/O, timer, or signal.
- **COMPLETED:** Terminated normally; result stored in `task.result`.
- **FAILED:** Terminated due to unhandled exception; error stored in `task.error`.

---

## 4. Backpressure and Resource Management

To prevent resource exhaustion under heavy concurrency:
1. **Bounded Mailboxes:** `SignalChannel` enforces capacity limits. If a mailbox exceeds capacity, additional signals are rejected until the workflow consumes pending messages.
2. **Cooperative Scheduling Loops:** `engine.runUntilComplete(workflowId, maxSteps)` bounds the maximum number of scheduling iterations, preventing infinite loops in buggy workflows from freezing the daemon.
3. **Low Stack Footprint:** Because fibers do not allocate separate OS thread stacks (typically 1 to 8 MB each), Keelson can maintain over 50,000 concurrent paused workflows in less than 200 MB of physical RAM.
