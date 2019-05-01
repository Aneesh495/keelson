// Unit tests for Keelson WorkflowSnapshot and LogCompactor.

import "../test_framework" for TestRunner
import "../../src/wren/storage/snapshot" for WorkflowSnapshot
import "../../src/wren/storage/compactor" for LogCompactor
import "../../src/wren/core/event_log" for EventLog, EventType
import "../../src/wren/core/workflow" for Workflow

TestRunner.describe("Workflow State Snapshotting and Log Compaction", Fn.new {
  TestRunner.test("snapshot captures and serializes point-in-time state", Fn.new {
    var snap = WorkflowSnapshot.new("wf-snap-1", 100, "RUNNING", {"balance": 1500, "tier": "gold"}, 5000)
    TestRunner.assertEqual("wf-snap-1", snap.workflowId)
    TestRunner.assertEqual(100, snap.snapshotIndex)
    TestRunner.assertEqual("RUNNING", snap.state)
    TestRunner.assertEqual(1500, snap.context["balance"])

    var json = snap.toJson()
    var restored = WorkflowSnapshot.fromJson(json)
    TestRunner.assertEqual("wf-snap-1", restored.workflowId)
    TestRunner.assertEqual(100, restored.snapshotIndex)
    TestRunner.assertEqual("gold", restored.context["tier"])
  })

  TestRunner.test("compactor truncates antecedent events", Fn.new {
    var compactor = LogCompactor.new(5)
    var log = EventLog.new("wf-compaction")

    // Append 8 events
    for (i in 1..8) {
      log.append(EventType.ACTIVITY_COMPLETED, 1000 + i, {"step": i})
    }
    TestRunner.assertEqual(8, log.count)
    TestRunner.assertTrue(compactor.shouldSnapshot(log))

    // Snapshot at event 5
    var snap = WorkflowSnapshot.new("wf-compaction", 5, "RUNNING", {"progress": 5}, 1005)

    // Compact log
    var compacted = compactor.compact(log, snap)

    // Events 1..5 trimmed, events 6, 7, 8 remain (3 events)
    TestRunner.assertEqual(3, compacted.count)
    TestRunner.assertEqual(6, compacted[0].eventId)
    TestRunner.assertEqual(7, compacted[1].eventId)
    TestRunner.assertEqual(8, compacted[2].eventId)
  })
})
