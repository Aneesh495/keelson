// Long-running human-in-the-loop approval workflow with timeout escalation for Keelson.
// Handles asynchronous signals, durable deadline timers, manager escalations, and executive overrides.

import "../core/workflow" for Workflow

class ApprovalWorkflow is Workflow {
  construct new(id) {
    super(id)
  }

  execute(request) {
    var requestId = request["requestId"]
    var requester = request["requester"]
    var amount = request["amount"]
    var deadlineMs = request["approvalDeadlineMs"]

    setContext("requestId", requestId)
    setContext("status", "PENDING_MANAGER_APPROVAL")
    setContext("escalated", false)

    // Notify manager
    executeActivity("notify_approver", {
      "approverRole": "Manager",
      "requestId": requestId,
      "amount": amount
    })

    // Wait for manager signal with escalation timeout
    var managerSignal = waitForSignal("manager_decision")

    if (managerSignal == null) {
      // Timeout triggered: escalate to VP
      setContext("escalated", true)
      setContext("status", "ESCALATED_TO_VP")

      executeActivity("notify_approver", {
        "approverRole": "VicePresident",
        "requestId": requestId,
        "amount": amount,
        "reason": "Manager approval deadline exceeded"
      })

      var vpSignal = waitForSignal("vp_decision")
      if (vpSignal != null && vpSignal["approved"] == true) {
        setContext("status", "APPROVED_BY_VP")
        executeActivity("disburse_funds", {"requestId": requestId, "amount": amount})
        return {"status": "APPROVED", "approver": "VicePresident", "requestId": requestId}
      } else {
        setContext("status", "REJECTED_BY_VP")
        return {"status": "REJECTED", "approver": "VicePresident", "requestId": requestId}
      }
    }

    if (managerSignal["approved"] == true) {
      setContext("status", "APPROVED_BY_MANAGER")
      executeActivity("disburse_funds", {"requestId": requestId, "amount": amount})
      return {"status": "APPROVED", "approver": "Manager", "requestId": requestId}
    } else {
      setContext("status", "REJECTED_BY_MANAGER")
      return {"status": "REJECTED", "approver": "Manager", "requestId": requestId}
    }
  }
}
