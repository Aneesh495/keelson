# Distributed Saga Orchestration and Backward Recovery

## 1. Overview and Problem Statement

In distributed architectures, multi-step business transactions span independent services, databases, and third-party APIs. Traditional distributed transactions relying on Two-Phase Commit (2PC) introduce severe bottlenecks:
- Coordinators hold locks across network boundaries, causing cascading latency.
- Participant outages block all participants, violating availability.
- Heterogeneous third-party systems (such as payment gateways and cloud providers) rarely support XA/2PC protocols.

The Saga Pattern resolves this by structuring a long-lived transaction as a sequence of local transactions:
$$T_1, T_2, T_3, \dots, T_n$$

Each local transaction $T_i$ commits its work locally and publishes an immutable event. If any step $T_k$ fails ($1 \le k \le n$), the saga orchestrator executes compensating transactions:
$$C_{k-1}, C_{k-2}, \dots, C_1$$

These compensating transactions act as semantic undo operations, restoring system state to a consistent baseline.

```
Forward Execution:
[Step 1: Lock Inventory] ---> [Step 2: Charge Payment] ---> [Step 3: Fraud Check (FAIL!)]
                                                                     |
                                                                     v
Backward Compensation:                                         Trips Rollback
[Comp 1: Unlock Inventory] <-- [Comp 2: Refund Payment] <------------+
```

---

## 2. Forward vs Backward Recovery

Keelson supports both recovery modalities:

### 2.1 Forward Recovery
When a step encounters a transient fault (network timeout, rate limit, socket reset), forward recovery attempts to complete the step successfully:
- Handled by `RetryPolicy` with exponential backoff and jitter strategies (`FULL`, `EQUAL`, `DECORRELATED`).
- Idempotency managers ensure that re-issued requests do not cause duplicate side effects.

### 2.2 Backward Recovery
When a step encounters an unrecoverable business failure (e.g. card declined, fraud score exceeded, insufficient stock, quota exceeded):
- Forward execution halts immediately.
- The saga status transitions to `COMPENSATING`.
- Steps that completed prior to failure are compensated in exact reverse order (LIFO).
- Upon completion of all compensations, the saga enters `COMPENSATED`.

---

## 3. Idempotency Guarantees for Compensations

A fundamental principle of resilient sagas is that **every compensating action must be idempotent**:
1. **Network Retries:** If a compensation request times out, Keelson may re-execute the compensation handler.
2. **Crash During Rollback:** If the engine host crashes halfway through compensation, the replay engine resumes compensation at the last uncompensated step.
3. **Payload Verification:** Keelson tracks compensation execution using 64-bit FNV-1a payload hashes to prevent duplicate refunds or releases.

---

## 4. Hierarchical Nested Sagas

Complex systems often require multi-tier workflows where a sub-component is itself a multi-step saga. Keelson natively supports nested sagas:

```
Parent Saga: Order Fulfillment
├── Step 1: Reserve Inventory
├── Step 2: Payment Sub-Saga (Nested)
│   ├── Sub-step 2.1: Credit Authorization
│   ├── Sub-step 2.2: Loyalty Points Deduction (FAILS!)
│   └── Sub-comp 2.1: Reverse Credit Authorization
└── Step 1 Comp: Release Inventory (Triggered by parent)
```

When a nested sub-saga fails:
1. The sub-saga executes its own local compensations in reverse order.
2. The sub-saga propagates failure to the parent saga.
3. The parent saga halts forward execution and triggers its remaining compensations.

---

## 5. Compensation Failure Handling

What happens when a compensation step itself throws an exception?
Keelson provides deterministic isolation:
- The error is captured in `SagaStep.compensationError`.
- The failed step is appended to `Saga.failedCompensations`.
- The orchestrator continues compensating remaining antecedent steps to prevent leaving the rest of the system unrecovered.
- The final saga status transitions to `COMPENSATION_FAILED`, producing a detailed audit report for operational alerting.

---

## 6. Implementation Example in Wren

```wren
import "keelson" for Saga

var saga = Saga.new("order-workflow-4412")

// Step 1: Inventory
saga.addStep("lock_inventory", Fn.new { |ctx|
  var token = Warehouse.reserve("SKU-9901")
  return {"reservationToken": token}
}, Fn.new { |res, ctx|
  Warehouse.release(res["reservationToken"])
})

// Step 2: Payment
saga.addStep("charge_payment", Fn.new { |ctx|
  var charge = Gateway.charge(9900)
  return {"txnId": charge.id}
}, Fn.new { |res, ctx|
  Gateway.refund(res["txnId"])
})

// Step 3: Shipping
saga.addStep("dispatch_carrier", Fn.new { |ctx|
  // If this throws, Step 2 then Step 1 are automatically compensated
  return Carrier.bookShipment("overnight")
}, Fn.new { |res, ctx|
  Carrier.cancelShipment(res["trackingNumber"])
})

var success = saga.execute()
if (!success) {
  System.print("Order failed. Rollback executed cleanly.")
}
```
