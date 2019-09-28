# Keelson API Reference

This document provides a comprehensive API reference for both the Wren core execution engine and the Python client SDK.

---

## 1. Wren Core API

Import the complete unified engine facade via:
```wren
import "keelson" for KeelsonEngine, Saga, Workflow, RetryPolicy, CircuitBreaker
```

### 1.1 `KeelsonEngine`
Central workflow orchestrator managing fibers, activities, event journals, and storage.

```wren
var engine = KeelsonEngine.new(storage)
```

- `registerActivity(name, fn)`: Registers a named activity handler closure.
- `startWorkflow(id, workflow, input)`: Spawns a new workflow instance.
- `step()`: Executes the single next highest-priority task from the scheduler heap.
- `runUntilComplete(workflowId, maxSteps)`: Executes scheduling loops until the workflow completes or fails. Returns `WorkflowInstance`.
- `sendSignal(workflowId, channel, data)`: Delivers an asynchronous payload to the workflow's signal mailbox.
- `query(workflowId, queryType, args)`: Dispatches a read-only state query without side effects.
- `metrics`: Returns the active `MetricsRegistry` for Prometheus telemetry.

---

### 1.2 `Saga`
Distributed saga orchestrator providing forward execution and reverse compensation.

```wren
var saga = Saga.new("order-saga-101")
```

- `addStep(name, forwardFn, compensationFn)`: Appends a saga step with forward execution closure and compensating rollback closure.
- `execute()`: Runs all steps in sequence. If any step aborts, halts forward execution and runs compensations in reverse order. Returns `true` on success, `false` on failure.
- `results`: Map containing outputs from each completed forward step.
- `status`: Current lifecycle string (`"PENDING"`, `"RUNNING"`, `"COMPLETED"`, `"COMPENSATED"`, `"COMPENSATION_FAILED"`).
- `compensationOrder`: List of step names executed during rollback.

---

### 1.3 `RetryPolicy`
Exponential backoff calculator with jitter strategies.

```wren
var policy = RetryPolicy.new(
  maxAttempts,         // Number of total retries allowed
  initialIntervalMs,   // Initial backoff delay (e.g. 100)
  maxIntervalMs,       // Delay ceiling (e.g. 10000)
  backoffMultiplier,   // Backoff factor (e.g. 2.0)
  jitterStrategy       // "NONE", "FULL", "EQUAL", or "DECORRELATED"
)
```

- `calculateDelay(attempt)`: Returns backoff duration in milliseconds for the given attempt index.
- `shouldRetry(attempt, error)`: Returns `true` if attempt count has not exceeded maximum and error is retryable.
- `addNonRetryableError(errorClass)`: Excludes specific error types from triggering retries.

---

### 1.4 `DAGOrchestrator`
Directed Acyclic Graph coordinator with Kahn topological sorting and join barriers.

```wren
var dag = DAGOrchestrator.new()
```

- `addNode(id, taskFn)`: Registers a discrete task node.
- `addDependency(parentId, childId)`: Defines an execution edge ($parent \to child$).
- `joinAll()`: Barrier waiting for all antecedent branches to complete.
- `joinAny()`: Barrier returning the result of the fastest branch.
- `joinQuorum(threshold)`: Barrier succeeding as soon as $M$ out of $N$ branches report success.

---

## 2. Python Client SDK

Install the package via standard tools:
```bash
cd sdk/python && pip install .
```

### 2.1 `KeelsonClient`

```python
from keelson import KeelsonClient

client = KeelsonClient(endpoint="http://127.0.0.1:8080", timeout=10.0)
```

#### Methods

- `client.health() -> EngineHealth`
  Inspects daemon status, uptime, active fiber count, and total events.

- `client.metrics() -> str`
  Fetches raw Prometheus exposition metrics text.

- `client.start_workflow(workflow_type: str, input_data: dict = None, workflow_id: str = None) -> WorkflowInstance`
  Dispatches a new workflow instance for asynchronous execution.

- `client.get_workflow(workflow_id: str) -> WorkflowInstance`
  Retrieves current status, execution metadata, and return result or error.

- `client.send_signal(workflow_id: str, channel: str, data: Any) -> bool`
  Transmits an asynchronous signal to a waiting workflow mailbox.

- `client.get_history(workflow_id: str) -> List[EventRecord]`
  Retrieves the complete immutable event sourcing journal for the workflow.

- `client.query(workflow_id: str, query_type: str, args: dict = None) -> QueryResponse`
  Executes a synchronous, side-effect-free state inspection query.

- `client.wait_for_completion(workflow_id: str, poll_interval: float = 0.5, max_wait_seconds: float = 30.0) -> WorkflowInstance`
  Blocks until the workflow reaches a terminal status (`COMPLETED`, `FAILED`, `COMPENSATED`, `CANCELLED`).

---

## 3. HTTP REST API Reference

The C host daemon exposes a RESTful HTTP/1.1 API on default port `8080`.

| Method | Path | Request Body | Description |
|---|---|---|---|
| `GET` | `/health` | None | Returns JSON engine health diagnostics. |
| `GET` | `/metrics` | None | Returns Prometheus text format telemetry. |
| `POST` | `/api/v1/workflows` | `{"workflow_type": "...", "input": {...}}` | Starts a new workflow instance. |
| `GET` | `/api/v1/workflows/{id}` | None | Retrieves workflow state and execution result. |
| `POST` | `/api/v1/workflows/{id}/signals` | `{"channel": "...", "data": {...}}` | Sends an asynchronous signal. |
| `GET` | `/api/v1/workflows/{id}/events` | None | Streams or retrieves complete event history. |
| `POST` | `/api/v1/workflows/{id}/queries` | `{"query_type": "...", "args": {...}}` | Dispatches a read-only state query. |
