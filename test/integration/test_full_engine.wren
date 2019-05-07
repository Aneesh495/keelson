// End-to-end integration tests for KeelsonEngine.

import "../test_framework" for TestRunner
import "../../src/wren/keelson" for KeelsonEngine, Workflow, MemoryLogStorage

class UserOnboardingWorkflow is Workflow {
  construct new(id) { super(id) }

  execute(input) {
    // 1. Create database user record
    var userRecord = executeActivity("create_user_record", {
      "username": input["username"],
      "email": input["email"]
    })

    // 2. Provision default storage workspace
    var workspace = executeActivity("provision_workspace", {
      "userId": userRecord["id"],
      "tier": input["tier"]
    })

    // 3. Send welcome email notification
    var email = executeActivity("send_welcome_email", {
      "email": input["email"],
      "workspaceId": workspace["workspaceId"]
    })

    return {
      "status": "ONBOARDED",
      "userId": userRecord["id"],
      "workspace": workspace["workspaceId"]
    }
  }
}

TestRunner.describe("KeelsonEngine End-to-End Workflow Execution", Fn.new {
  TestRunner.test("engine executes multi-step activity workflow to completion", Fn.new {
    var storage = MemoryLogStorage.new()
    var engine = KeelsonEngine.new(storage)

    // Register activity handlers
    engine.registerActivity("create_user_record", Fn.new { |input|
      return {"id": "usr_789", "username": input["username"]}
    })

    engine.registerActivity("provision_workspace", Fn.new { |input|
      return {"workspaceId": "ws_alpha", "quotaGb": 50}
    })

    engine.registerActivity("send_welcome_email", Fn.new { |input|
      return {"delivered": true, "messageId": "msg_001"}
    })

    // Start workflow
    var wf = UserOnboardingWorkflow.new("onboard-42")
    var record = engine.startWorkflow("onboard-42", wf, {
      "username": "aneesh",
      "email": "aneesh@example.com",
      "tier": "enterprise"
    })

    TestRunner.assertEqual("RUNNING", record.status)

    // Run engine to completion
    var completed = engine.runUntilComplete("onboard-42", 50)

    TestRunner.assertNotNull(completed)
    TestRunner.assertEqual("COMPLETED", completed.status)
    TestRunner.assertEqual("ONBOARDED", completed.result["status"])
    TestRunner.assertEqual("usr_789", completed.result["userId"])
    TestRunner.assertEqual("ws_alpha", completed.result["workspace"])

    // Verify engine metrics
    var metrics = engine.metrics
    TestRunner.assertEqual(1, metrics.counter("keelson_workflows_started_total", "total").value)
    TestRunner.assertEqual(1, metrics.counter("keelson_workflows_completed_total", "completed").value)
    TestRunner.assertEqual(3, metrics.counter("keelson_activities_executed_total", "acts").value)
  })
})
