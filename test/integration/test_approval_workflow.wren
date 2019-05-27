// Integration tests for Human-in-the-Loop Approval and Escalation Workflow.

import "../test_framework" for TestRunner
import "../../src/wren/workflows/approval_escalation_workflow" for ApprovalWorkflow
import "../../src/wren/keelson" for KeelsonEngine, MemoryLogStorage

TestRunner.describe("Approval Escalation Workflow", Fn.new {
  TestRunner.test("direct manager approval disburses funds", Fn.new {
    var storage = MemoryLogStorage.new()
    var engine = KeelsonEngine.new(storage)

    var notified = []
    var disbursed = []

    engine.registerActivity("notify_approver", Fn.new { |input|
      notified.add(input["approverRole"])
      return {"sent": true}
    })

    engine.registerActivity("disburse_funds", Fn.new { |input|
      disbursed.add(input["amount"])
      return {"tx": "DISBURSE-OK"}
    })

    var wf = ApprovalWorkflow.new("appr-wf-1")
    engine.startWorkflow("appr-wf-1", wf, {
      "requestId": "REQ-771",
      "requester": "alice",
      "amount": 4500,
      "approvalDeadlineMs": 86400000
    })

    // Step to execute notify_approver and reach waitForSignal
    engine.step()

    // Deliver manager decision signal
    engine.sendSignal("appr-wf-1", "manager_decision", {
      "approved": true,
      "notes": "Approved for Q4 equipment"
    })

    // Run to completion
    var completed = engine.runUntilComplete("appr-wf-1", 20)

    TestRunner.assertNotNull(completed)
    TestRunner.assertEqual("COMPLETED", completed.status)
    TestRunner.assertEqual("APPROVED", completed.result["status"])
    TestRunner.assertEqual("Manager", completed.result["approver"])
    TestRunner.assertEqual("REQ-771", completed.result["requestId"])
    TestRunner.assertEqual(1, disbursed.count)
    TestRunner.assertEqual(4500, disbursed[0])
  })

  TestRunner.test("missing manager signal escalates to VP with executive approval", Fn.new {
    var storage = MemoryLogStorage.new()
    var engine = KeelsonEngine.new(storage)

    var rolesNotified = []
    var disbursed = []

    engine.registerActivity("notify_approver", Fn.new { |input|
      rolesNotified.add(input["approverRole"])
      return {"sent": true}
    })

    engine.registerActivity("disburse_funds", Fn.new { |input|
      disbursed.add(input["amount"])
      return {"tx": "DISBURSE-VP-OVERRIDE"}
    })

    var wf = ApprovalWorkflow.new("appr-wf-vp")
    engine.startWorkflow("appr-wf-vp", wf, {
      "requestId": "REQ-BIG-99",
      "requester": "bob",
      "amount": 95000,
      "approvalDeadlineMs": 86400000
    })

    // Step once to execute initial notify_approver
    engine.step()

    // Resume without manager signal to simulate timeout expiration
    engine.fiberPool.resume("appr-wf-vp", 10)
    engine.step()

    // Verify escalation notification went to VicePresident
    TestRunner.assertTrue(rolesNotified.contains("VicePresident"))

    // Deliver VP decision signal
    engine.sendSignal("appr-wf-vp", "vp_decision", {
      "approved": true,
      "notes": "Executive override granted by VP"
    })

    // Run to completion
    var completed = engine.runUntilComplete("appr-wf-vp", 20)

    TestRunner.assertNotNull(completed)
    TestRunner.assertEqual("COMPLETED", completed.status)
    TestRunner.assertEqual("APPROVED", completed.result["status"])
    TestRunner.assertEqual("VicePresident", completed.result["approver"])
    TestRunner.assertEqual(1, disbursed.count)
    TestRunner.assertEqual(95000, disbursed[0])
  })
})
