// Tests for crash recovery and live execution continuation after event replay.

import "../test_framework" for TestRunner
import "../../src/wren/core/workflow" for Workflow
import "../../src/wren/core/event_log" for EventLog, EventType

class CrashRecoveryWorkflow is Workflow {
  construct new(id) { super(id) }

  execute(input) {
    var step1 = executeActivity("step_one", {"val": input["val"]})
    setContext("step1_out", step1)

    // Crash happened right here in historical run!
    var step2 = executeActivity("step_two", {"derived": step1 * 2})
    setContext("step2_out", step2)

    return {"final": step2 + 10}
  }
}

TestRunner.describe("Crash Recovery and Continuation", Fn.new {
  TestRunner.test("replays up to crash point and yields for live activity execution", Fn.new {
    // History contains only step_one completed
    var history = EventLog.new("wf-crash-sim")
    history.append(EventType.WORKFLOW_STARTED, 100, {"val": 5})
    history.append(EventType.ACTIVITY_COMPLETED, 110, {"activityId": "act-1", "result": 10})

    var wf = CrashRecoveryWorkflow.new("wf-crash-sim")
    wf.attachHistory(history)

    // Execute in fiber to intercept yield on step_two
    var fiber = Fiber.new(Fn.new {
      return wf.execute({"val": 5})
    })

    // Run until fiber yields on live activity step_two
    var yieldVal = fiber.call()

    // Verify step_one was fast-forwarded from cache
    TestRunner.assertEqual(10, wf.query("step1_out"))

    // Verify fiber yielded requesting live execution of step_two
    TestRunner.assertNotNull(yieldVal)
    TestRunner.assertEqual("ACTIVITY", yieldVal["type"])
    TestRunner.assertEqual("act-2", yieldVal["activityId"])
    TestRunner.assertEqual("step_two", yieldVal["activityName"])
    TestRunner.assertEqual(20, yieldVal["input"]["derived"])

    // Deliver live activity result back to the fiber
    var finalResult = fiber.call(40)

    // Verify workflow completed with final calculation (40 + 10 = 50)
    TestRunner.assertEqual(50, finalResult["final"])
    TestRunner.assertEqual(40, wf.query("step2_out"))
  })
})
