// Unit tests for Keelson FiberPool and cooperative task scheduler.

import "../test_framework" for TestRunner
import "../../src/wren/core/fiber_pool" for FiberPool

TestRunner.describe("FiberPool Scheduling and Concurrency", Fn.new {
  TestRunner.test("spawn and complete simple fiber task", Fn.new {
    var pool = FiberPool.new()
    var executed = false

    pool.spawn("task-1", Fn.new {
      executed = true
    })

    TestRunner.assertEqual(1, pool.queueCount)
    var stepped = pool.step()
    TestRunner.assertTrue(stepped)
    TestRunner.assertTrue(executed)
    TestRunner.assertEqual(0, pool.queueCount)
    TestRunner.assertEqual(1, pool.completedCount)
  })

  TestRunner.test("cooperative yield and resumption", Fn.new {
    var pool = FiberPool.new()
    var log = []

    pool.spawn("yield-task", Fn.new {
      log.add("step-1")
      FiberPool.yield()
      log.add("step-2")
    })

    // First step should execute step-1 and suspend
    pool.step()
    TestRunner.assertEqual(1, log.count)
    TestRunner.assertEqual("step-1", log[0])

    var task = pool.getTask("yield-task")
    TestRunner.assertEqual("SUSPENDED", task.state)

    // Re-schedule and execute second step
    pool.resume("yield-task", 10)
    pool.step()

    TestRunner.assertEqual(2, log.count)
    TestRunner.assertEqual("step-2", log[1])
    TestRunner.assertEqual("COMPLETED", task.state)
  })

  TestRunner.test("priority ordering across concurrent fibers", Fn.new {
    var pool = FiberPool.new()
    var executionOrder = []

    pool.spawnWithPriority("low", 100, null, Fn.new {
      executionOrder.add("low")
    })

    pool.spawnWithPriority("high", 10, null, Fn.new {
      executionOrder.add("high")
    })

    pool.spawnWithPriority("medium", 50, null, Fn.new {
      executionOrder.add("medium")
    })

    pool.runUntilQuiescent(10)

    TestRunner.assertEqual(3, executionOrder.count)
    TestRunner.assertEqual("high", executionOrder[0])
    TestRunner.assertEqual("medium", executionOrder[1])
    TestRunner.assertEqual("low", executionOrder[2])
  })

  TestRunner.test("error isolation prevents pool crash", Fn.new {
    var pool = FiberPool.new()

    pool.spawn("failing-task", Fn.new {
      Fiber.abort("Simulated catastrophic fiber error")
    })

    pool.step()

    var task = pool.getTask("failing-task")
    TestRunner.assertEqual("FAILED", task.state)
    TestRunner.assertNotNull(task.error)
    TestRunner.assertEqual(1, pool.failedCount)
    TestRunner.assertEqual(0, pool.completedCount)
  })
})
