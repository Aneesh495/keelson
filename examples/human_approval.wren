// Runnable demonstration of Keelson human-in-the-loop approval workflow.
// Demonstrates asynchronous signal handling, durable deadline timers,
// manager approval routing, and automated escalation to VP on timeout.

import "../src/wren/workflows/approval_escalation_workflow" for ApprovalWorkflow
import "../src/wren/keelson" for KeelsonEngine, MemoryLogStorage

System.print("============================================================")
System.print("   KEELSON: HUMAN-IN-THE-LOOP APPROVAL ESCALATION DEMO      ")
System.print("============================================================")

// Scenario 1: Immediate manager approval
System.print("\n>>> SCENARIO 1: Standard capital expenditure approval by direct manager")
System.print("------------------------------------------------------------")

var storage1 = MemoryLogStorage.new()
var engine1 = KeelsonEngine.new(storage1)

engine1.registerActivity("notify_approver", Fn.new { |input|
  System.print("  [NOTIFY] Alerted %(input["approverRole"]) regarding %(input["requestId"]) for $%(input["amount"])")
  return {"delivered": true}
})

engine1.registerActivity("disburse_funds", Fn.new { |input|
  System.print("  [DISBURSE] Wire transfer executed for $%(input["amount"])")
  return {"tx": "WIRE-OK-9912"}
})

var wf1 = ApprovalWorkflow.new("wf-capex-001")
engine1.startWorkflow("wf-capex-001", wf1, {
  "requestId": "REQ-88912",
  "requester": "Engineering Team",
  "amount": 25000,
  "approvalDeadlineMs": 48 * 3600 * 1000
})

// Step to execute notify_approver and reach waitForSignal
engine1.step()

// Deliver manager decision signal
System.print("  [SIGNAL] Manager approved request REQ-88912")
engine1.sendSignal("wf-capex-001", "manager_decision", {
  "approved": true,
  "notes": "Budget allocated in Q4 equipment budget"
})

var completed1 = engine1.runUntilComplete("wf-capex-001", 20)
System.print("Outcome:          %(completed1.result["status"])")
System.print("Approver:         %(completed1.result["approver"])")
System.print("Request ID:       %(completed1.result["requestId"])")

// Scenario 2: Manager unresponsive, escalates to VP
System.print("\n>>> SCENARIO 2: Manager unresponsiveness triggering executive escalation")
System.print("------------------------------------------------------------")

var storage2 = MemoryLogStorage.new()
var engine2 = KeelsonEngine.new(storage2)

engine2.registerActivity("notify_approver", Fn.new { |input|
  var reason = input["reason"] != null ? " Reason: " + input["reason"] : ""
  System.print("  [NOTIFY] Alerted %(input["approverRole"]) regarding %(input["requestId"]) for $%(input["amount"]).%(reason)")
  return {"delivered": true}
})

engine2.registerActivity("disburse_funds", Fn.new { |input|
  System.print("  [DISBURSE] Executive override wire transfer executed for $%(input["amount"])")
  return {"tx": "WIRE-EXEC-4421"}
})

var wf2 = ApprovalWorkflow.new("wf-capex-002")
engine2.startWorkflow("wf-capex-002", wf2, {
  "requestId": "REQ-88913",
  "requester": "Infrastructure Team",
  "amount": 120000,
  "approvalDeadlineMs": 24 * 3600 * 1000
})

// Step once to execute initial notify_approver
engine2.step()

// Simulate deadline expiration: resume fiber without manager signal
System.print("  [TIMER] 24-hour manager approval deadline expired with no response")
System.print("  [ESCALATION] Automatically escalating to VicePresident")
engine2.fiberPool.resume("wf-capex-002", 10)
engine2.step()

// Deliver VP decision signal
System.print("  [SIGNAL] VicePresident approved emergency compute capacity")
engine2.sendSignal("wf-capex-002", "vp_decision", {
  "approved": true,
  "notes": "Executive override granted for cluster scaling"
})

var completed2 = engine2.runUntilComplete("wf-capex-002", 20)
System.print("Outcome:          %(completed2.result["status"])")
System.print("Approver:         %(completed2.result["approver"]) (Executive Override)")
System.print("Request ID:       %(completed2.result["requestId"])")

System.print("\n============================================================")
System.print("Human approval escalation demonstration completed.")
System.print("============================================================")
