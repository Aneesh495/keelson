// Unit tests for Keelson TimerWheel and DurableTimer.

import "../test_framework" for TestRunner
import "../../src/wren/core/timer" for TimerWheel

TestRunner.describe("TimerWheel Durable Scheduling", Fn.new {
  TestRunner.test("schedules and fires timers in monotonic chronological order", Fn.new {
    var wheel = TimerWheel.new()
    var firedOrder = []

    // Schedule 3 timers at t=1000:
    // Timer 1: 500ms delay -> fire at 1500
    // Timer 2: 200ms delay -> fire at 1200
    // Timer 3: 800ms delay -> fire at 1800
    wheel.schedule("t1", 500, 1000, Fn.new { |t| firedOrder.add("t1") })
    wheel.schedule("t2", 200, 1000, Fn.new { |t| firedOrder.add("t2") })
    wheel.schedule("t3", 800, 1000, Fn.new { |t| firedOrder.add("t3") })

    TestRunner.assertEqual(3, wheel.activeCount)
    TestRunner.assertEqual(1200, wheel.nextDeadline())

    // Advance to t=1100 (none expired)
    var fired1 = wheel.advance(1100)
    TestRunner.assertEqual(0, fired1.count)
    TestRunner.assertEqual(3, wheel.activeCount)

    // Advance to t=1300 (t2 expired)
    var fired2 = wheel.advance(1300)
    TestRunner.assertEqual(1, fired2.count)
    TestRunner.assertEqual("t2", fired2[0].id)
    TestRunner.assertEqual(2, wheel.activeCount)
    TestRunner.assertEqual(1500, wheel.nextDeadline())

    // Advance to t=2000 (t1 and t3 expired in order)
    var fired3 = wheel.advance(2000)
    TestRunner.assertEqual(2, fired3.count)
    TestRunner.assertEqual("t1", fired3[0].id)
    TestRunner.assertEqual("t3", fired3[1].id)
    TestRunner.assertEqual(0, wheel.activeCount)
    TestRunner.assertNull(wheel.nextDeadline())

    // Verify callback execution order
    TestRunner.assertEqual(3, firedOrder.count)
    TestRunner.assertEqual("t2", firedOrder[0])
    TestRunner.assertEqual("t1", firedOrder[1])
    TestRunner.assertEqual("t3", firedOrder[2])
  })

  TestRunner.test("cancelling a timer prevents it from firing", Fn.new {
    var wheel = TimerWheel.new()
    var fired = false

    wheel.schedule("cancel-target", 300, 1000, Fn.new { |t| fired = true })
    TestRunner.assertEqual(1, wheel.activeCount)

    var cancelled = wheel.cancel("cancel-target")
    TestRunner.assertTrue(cancelled)
    TestRunner.assertEqual(0, wheel.activeCount)

    // Advance clock past expiration
    var firedList = wheel.advance(2000)
    TestRunner.assertEqual(0, firedList.count)
    TestRunner.assertFalse(fired)
  })
})
