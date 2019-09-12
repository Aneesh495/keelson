# Deterministic Workflow Replay and Crash Recovery

## 1. Event Sourcing Foundation

In Keelson, workflow state is never mutated in place. Instead, state is derived as a pure, deterministic fold over an immutable, append-only sequence of historical events:

$$S_t = \text{foldl}(\text{applyEvent}, S_0, [e_1, e_2, \dots, e_t])$$

Where:
- $S_0$ is the initial workflow state at instantiation.
- $e_i$ is the $i$-th immutable `HistoryEvent` in the journal.
- $\text{applyEvent}(S, e)$ is a pure transition function returning the updated state.

```
+-----------------------------------------------------------------------+
|                       Immutable Event Journal                         |
|  [Event 1] ---> [Event 2] ---> [Event 3] ---> [Event 4] ---> [Crash!] |
+-----------------------------------------------------------------------+
        |                |              |               |
        v                v              v               v
  (Start Order)   (Reserve Stock) (Charge Card)   (Fraud Passed)
                         \              /
                          v            v
                 +-------------------------------+
                 |  Deterministic Replay Engine  |
                 |     (Side-Effect Caching)     |
                 +---------------+---------------+
                                 |
                     (Seamless Live Continuation)
                                 v
                 [Event 5: Dispatch Carrier (LIVE)]
```

---

## 2. Side-Effect Caching and Interception

When workflow code runs for the first time, activity invocations (such as sending an email or charging a credit card) perform live network I/O. The result of that activity is serialized and written to the event log.

During replay (whether for crash recovery, state inspection, or time-travel debugging):
1. Keelson sets `isReplaying = true`.
2. When the workflow calls `executeActivity(name, input)`, the replay engine intercepts the call.
3. Instead of dispatching network I/O, the engine looks ahead in the event journal for the corresponding `ACTIVITY_COMPLETED` record.
4. The cached output payload is returned immediately to the waiting fiber.
5. The activity handler is never executed twice, guaranteeing at-most-once execution for non-idempotent side effects.

---

## 3. Detecting Code Divergence (Non-Determinism)

Deterministic replay requires that the sequence of events requested by workflow code exactly matches the sequence recorded in history.

Non-determinism occurs if:
- Workflow code directly reads wall-clock time (`Date.now()`) or system random numbers instead of deterministic engine APIs (`context.timestamp`, `deterministicRandom()`).
- The developer deploys modified workflow code that alters activity order without versioning.

Keelson guards against non-determinism via strict event sequence verification:
- When an activity is scheduled, the engine compares its name and input against the next recorded event in the journal.
- If a discrepancy is detected, the engine raises `ReplayDivergenceError`:
  ```
  ReplayDivergenceError: Workflow non-determinism detected at sequence 4.
  Expected event: 'ACTIVITY_SCHEDULED:charge_payment'
  Actual code requested: 'ACTIVITY_SCHEDULED:send_receipt'
  ```
- This prevents silent corruption or invalid state transitions.

---

## 4. Crash Recovery and Continuation

If the host process crashes (due to power failure, operating system crash, or `SIGKILL`), Keelson restores the workflow seamlessly:

1. **WAL Scan:** On boot, the engine scans the binary WAL from the last checkpoint, validating 32-byte headers and IEEE 802.3 CRC32 checksums.
2. **Replay Phase:** The engine reconstructs the fiber pool and feeds the recorded events into the workflow instance until the event log is exhausted.
3. **Continuation Transition:** When the last historical event has been processed, `isReplaying` is cleared.
4. **Live Execution:** The workflow fiber resumes normal cooperative execution, dispatching live activities from the exact point of interruption.

---

## 5. Periodic Snapshotting and Log Compaction

For long-running workflows with thousands of events, replaying from event #1 introduces unnecessary latency. Keelson employs snapshotting to bound recovery time:

- **Snapshot Creation:** The `SnapshotManager` captures a point-in-time state dictionary and serializes it to disk using atomic write-rename semantics.
- **Log Compaction:** The `LogCompactor` archives or truncates historical events preceding the snapshot boundary.
- **Recovery Acceleration:** Replay loads the latest valid snapshot $S_k$ directly and replays only the delta events $[e_{k+1}, \dots, e_t]$, reducing cold-start recovery time from $O(N)$ to $O(1)$.
