// Unit tests for Keelson deterministic StateMachine.

import "../test_framework" for TestRunner
import "../../src/wren/core/state_machine" for StateMachine

TestRunner.describe("StateMachine Lifecycle and Transitions", Fn.new {
  TestRunner.test("initial state and configuration", Fn.new {
    var sm = StateMachine.new("Workflow", "CREATED")
    TestRunner.assertEqual("CREATED", sm.currentState)
    TestRunner.assertEqual("Workflow", sm.entityName)
    TestRunner.assertEqual(0, sm.history.count)
  })

  TestRunner.test("valid transitions execute cleanly", Fn.new {
    var sm = StateMachine.new("Task", "PENDING")
    sm.allow("PENDING", "RUNNING")
    sm.allow("RUNNING", "COMPLETED")

    TestRunner.assertTrue(sm.canTransitionTo("RUNNING"))
    TestRunner.assertFalse(sm.canTransitionTo("COMPLETED"))

    sm.transition("RUNNING")
    TestRunner.assertEqual("RUNNING", sm.currentState)
    TestRunner.assertEqual(1, sm.history.count)

    sm.transition("COMPLETED")
    TestRunner.assertEqual("COMPLETED", sm.currentState)
    TestRunner.assertEqual(2, sm.history.count)
  })

  TestRunner.test("forbidden transitions abort execution", Fn.new {
    var sm = StateMachine.new("Task", "PENDING")
    sm.allow("PENDING", "RUNNING")

    TestRunner.assertThrows(Fn.new {
      sm.transition("FAILED")
    }, "Transition to unallowed state must abort")
  })

  TestRunner.test("enter and exit hooks dispatch in correct order", Fn.new {
    var sm = StateMachine.new("Saga", "INIT")
    sm.allow("INIT", "EXECUTING")
    sm.allow("EXECUTING", "COMPENSATING")

    var events = []

    sm.onExit("INIT", Fn.new { |from, to, ctx|
      events.add("exit: " + from)
    })

    sm.onEnter("EXECUTING", Fn.new { |from, to, ctx|
      events.add("enter: " + to)
    })

    sm.transition("EXECUTING")

    TestRunner.assertEqual(2, events.count)
    TestRunner.assertEqual("exit: INIT", events[0])
    TestRunner.assertEqual("enter: EXECUTING", events[1])
  })

  TestRunner.test("rehydrate resets state for replay without side effects", Fn.new {
    var sm = StateMachine.new("Workflow", "CREATED")
    sm.allow("CREATED", "RUNNING")
    sm.rehydrate("COMPLETED")
    TestRunner.assertEqual("COMPLETED", sm.currentState)
  })
})
