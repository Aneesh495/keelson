// Unit tests for MemoryLogStorage and FileLogStorage.

import "io" for File, Directory
import "../test_framework" for TestRunner
import "../../src/wren/storage/memory_log" for MemoryLogStorage
import "../../src/wren/storage/file_log" for FileLogStorage
import "../../src/wren/core/event_log" for EventType, HistoryEvent

TestRunner.describe("Event Storage Engines", Fn.new {
  TestRunner.test("MemoryLogStorage creates and isolates workflow logs", Fn.new {
    var mem = MemoryLogStorage.new()
    TestRunner.assertEqual(0, mem.count)

    var log1 = mem.getOrCreate("wf-1")
    log1.append(EventType.WORKFLOW_STARTED, 100, {"name": "test"})
    TestRunner.assertEqual(1, mem.count)
    TestRunner.assertTrue(mem.has("wf-1"))

    var log2 = mem.getOrCreate("wf-2")
    TestRunner.assertEqual(2, mem.count)
    TestRunner.assertEqual(0, log2.count)

    mem.delete("wf-1")
    TestRunner.assertFalse(mem.has("wf-1"))
    TestRunner.assertEqual(1, mem.count)
  })

  TestRunner.test("FileLogStorage writes and reloads persistent events", Fn.new {
    var testDir = "./data/test_wal"
    var storage = FileLogStorage.new(testDir)
    var wfId = "persistent-wf-999"

    // Clean up any stale file from prior runs
    storage.deleteHistory(wfId)
    TestRunner.assertFalse(storage.hasHistory(wfId))

    // Write events
    var e1 = HistoryEvent.new(1, wfId, EventType.WORKFLOW_STARTED, 1000, {"amount": 500})
    var e2 = HistoryEvent.new(2, wfId, EventType.ACTIVITY_COMPLETED, 1100, {"receipt": "REC-42"})

    storage.appendEvent(e1)
    storage.appendEvent(e2)

    TestRunner.assertTrue(storage.hasHistory(wfId))

    // Reload from disk
    var reloadedLog = storage.loadHistory(wfId)
    TestRunner.assertEqual(2, reloadedLog.count)
    TestRunner.assertEqual(EventType.WORKFLOW_STARTED, reloadedLog[0].eventType)
    TestRunner.assertEqual(500, reloadedLog[0].attributes["amount"])
    TestRunner.assertEqual(EventType.ACTIVITY_COMPLETED, reloadedLog[1].eventType)
    TestRunner.assertEqual("REC-42", reloadedLog[1].attributes["receipt"])

    // Clean up
    storage.deleteHistory(wfId)
    TestRunner.assertFalse(storage.hasHistory(wfId))
  })
})
