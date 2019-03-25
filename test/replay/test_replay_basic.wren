// Unit tests for Keelson deterministic workflow replay engine.

import "../test_framework" for TestRunner
import "../../src/wren/core/workflow" for Workflow
import "../../src/wren/core/event_log" for EventLog, EventType

class TestOrderWorkflow is Workflow {
  construct new(id) { super(id) }

  execute(input) {
    var inv = executeActivity("reserve_inventory", {"sku": input["sku"]})
    setContext("inventory_res", inv)

    var pay = executeActivity("charge_card", {"amount": input["amount"]})
    setContext("payment_res", pay)

    sleep(100)
    setContext("timer_completed", true)

    return {"status": "SUCCESS", "orderId": input["orderId"]}
  }
}

TestRunner.describe("Deterministic Workflow Replay", Fn.new {
  TestRunner.test("replays completed workflow from event log without calling activities", Fn.new {
    // 1. Synthesize a recorded historical event log from a prior execution
    var history = EventLog.new("order-wf-replay-1")
    history.append(EventType.WORKFLOW_STARTED, 1000, {"orderId": "ORD-123", "amount": 99.95, "sku": "ITEM-X"})
    history.append(EventType.ACTIVITY_SCHEDULED, 1010, {"activityId": "act-1", "name": "reserve_inventory"})
    history.append(EventType.ACTIVITY_COMPLETED, 1020, {"activityId": "act-1", "result": {"reserved": true, "slot": "A1"}})
    history.append(EventType.ACTIVITY_SCHEDULED, 1030, {"activityId": "act-2", "name": "charge_card"})
    history.append(EventType.ACTIVITY_COMPLETED, 1040, {"activityId": "act-2", "result": {"auth": "AUTH-OK", "charged": 99.95}})
    history.append(EventType.TIMER_STARTED, 1050, {"timerId": "timer-1", "durationMs": 100})
    history.append(EventType.TIMER_FIRED, 1150, {"timerId": "timer-1"})

    // 2. Replay workflow against the history log
    var wf = TestOrderWorkflow.new("order-wf-replay-1")
    wf.attachHistory(history)

    var result = wf.execute({"orderId": "ORD-123", "amount": 99.95, "sku": "ITEM-X"})

    // 3. Verify workflow completed instantly from replay cache
    TestRunner.assertEqual("SUCCESS", result["status"])
    TestRunner.assertEqual("ORD-123", result["orderId"])

    // Verify context variables were restored identically
    TestRunner.assertEqual(true, wf.query("inventory_res")["reserved"])
    TestRunner.assertEqual("AUTH-OK", wf.query("payment_res")["auth"])
    TestRunner.assertEqual(true, wf.query("timer_completed"))
  })
})
