// Unit tests for Keelson EventLog and HistoryEvent event sourcing.

import "../test_framework" for TestRunner
import "../../src/wren/core/event_log" for EventLog, EventType, HistoryEvent

TestRunner.describe("EventLog and HistoryEvent Event Sourcing", Fn.new {
  TestRunner.test("append assigns monotonic event IDs", Fn.new {
    var log = EventLog.new("wf-order-1")
    TestRunner.assertEqual(0, log.count)

    var e1 = log.append(EventType.WORKFLOW_STARTED, 1000, {"amount": 200})
    var e2 = log.append(EventType.ACTIVITY_SCHEDULED, 1010, {"activity": "charge"})
    var e3 = log.append(EventType.ACTIVITY_COMPLETED, 1050, {"txId": "tx_abc"})

    TestRunner.assertEqual(3, log.count)
    TestRunner.assertEqual(1, e1.eventId)
    TestRunner.assertEqual(2, e2.eventId)
    TestRunner.assertEqual(3, e3.eventId)
    TestRunner.assertEqual("wf-order-1", e1.workflowId)
  })

  TestRunner.test("findEvents filters by type", Fn.new {
    var log = EventLog.new("wf-filter")
    log.append(EventType.ACTIVITY_SCHEDULED, 10, {"name": "act1"})
    log.append(EventType.ACTIVITY_COMPLETED, 20, {"name": "act1"})
    log.append(EventType.ACTIVITY_SCHEDULED, 30, {"name": "act2"})

    var scheduled = log.findEvents(EventType.ACTIVITY_SCHEDULED)
    TestRunner.assertEqual(2, scheduled.count)
    TestRunner.assertEqual("act1", scheduled[0].attributes["name"])
    TestRunner.assertEqual("act2", scheduled[1].attributes["name"])

    var lastScheduled = log.findLast(EventType.ACTIVITY_SCHEDULED)
    TestRunner.assertEqual("act2", lastScheduled.attributes["name"])
  })

  TestRunner.test("serialization round-trip via JSON restores exact history", Fn.new {
    var original = EventLog.new("wf-serial-test")
    original.append(EventType.WORKFLOW_STARTED, 1000, {"input": "test-data"})
    original.append(EventType.ACTIVITY_COMPLETED, 1500, {"status": "SUCCESS", "code": 200})

    var jsonString = original.toJson()
    var restored = EventLog.fromJson("wf-serial-test", jsonString)

    TestRunner.assertEqual(2, restored.count)
    TestRunner.assertEqual(EventType.WORKFLOW_STARTED, restored[0].eventType)
    TestRunner.assertEqual("test-data", restored[0].attributes["input"])
    TestRunner.assertEqual(2, restored[1].eventId)
    TestRunner.assertEqual(200, restored[1].attributes["code"])

    // Subsequent append must continue monotonic sequencing
    var e3 = restored.append(EventType.WORKFLOW_COMPLETED, 2000, {"result": "ok"})
    TestRunner.assertEqual(3, e3.eventId)
  })
})
