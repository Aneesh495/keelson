// Unit tests for Keelson ActivityTask, ActivityDefinition, and ActivityRegistry.

import "../test_framework" for TestRunner
import "../../src/wren/core/activity" for ActivityTask, ActivityStatus, ActivityRegistry

TestRunner.describe("Activity Lifecycle and Execution Registry", Fn.new {
  TestRunner.test("activity task status lifecycle", Fn.new {
    var task = ActivityTask.new("act-1", "charge_card", {"amount": 50}, null, 5000)
    TestRunner.assertEqual("PENDING", task.status)
    TestRunner.assertFalse(task.isTerminal)

    task.markStarted(1000)
    TestRunner.assertEqual("RUNNING", task.status)
    TestRunner.assertEqual(1000, task.startedAt)

    task.markCompleted({"txId": "ch_999"}, 1050)
    TestRunner.assertEqual("COMPLETED", task.status)
    TestRunner.assertTrue(task.isTerminal)
    TestRunner.assertEqual("ch_999", task.result["txId"])
  })

  TestRunner.test("registry executes registered handler successfully", Fn.new {
    var registry = ActivityRegistry.new()
    registry.registerHandler("compute_hash", Fn.new { |input|
      return "hash:" + input["data"].toString
    })

    var task = ActivityTask.new("act-2", "compute_hash", {"data": "keelson"}, null, 1000)
    registry.execute(task, 2000)

    TestRunner.assertEqual(ActivityStatus.COMPLETED, task.status)
    TestRunner.assertEqual("hash:keelson", task.result)
  })

  TestRunner.test("registry isolates activity faults and records error", Fn.new {
    var registry = ActivityRegistry.new()
    registry.registerHandler("unreliable_api", Fn.new { |input|
      Fiber.abort("Gateway timeout 504")
    })

    var task = ActivityTask.new("act-3", "unreliable_api", {}, null, 1000)
    registry.execute(task, 3000)

    TestRunner.assertEqual(ActivityStatus.FAILED, task.status)
    TestRunner.assertNotNull(task.error)
    TestRunner.assertTrue(task.error.toString.contains("Gateway timeout 504"))
  })

  TestRunner.test("unregistered activity marks task failed immediately", Fn.new {
    var registry = ActivityRegistry.new()
    var task = ActivityTask.new("act-4", "missing_service", {}, null, 1000)
    registry.execute(task, 4000)

    TestRunner.assertEqual(ActivityStatus.FAILED, task.status)
    TestRunner.assertTrue(task.error.toString.contains("Unregistered activity"))
  })
})
