// Unit tests for Keelson DAG and join barrier patterns.

import "../test_framework" for TestRunner
import "../../src/wren/core/dag" for Dag

TestRunner.describe("DAG Orchestrator and Join Patterns", Fn.new {
  TestRunner.test("topological sort executes in correct dependency order", Fn.new {
    var dag = Dag.new()
    var executionTrace = []

    // Task A has no deps
    dag.addNode("A", Fn.new { |deps|
      executionTrace.add("A")
      return 10
    })

    // Task B depends on A
    dag.addNode("B", Fn.new { |deps|
      executionTrace.add("B")
      return deps["A"] * 2
    })
    dag.addDependency("B", "A")

    // Task C depends on A
    dag.addNode("C", Fn.new { |deps|
      executionTrace.add("C")
      return deps["A"] + 5
    })
    dag.addDependency("C", "A")

    // Task D depends on B and C
    dag.addNode("D", Fn.new { |deps|
      executionTrace.add("D")
      return deps["B"] + deps["C"]
    })
    dag.addDependency("D", "B")
    dag.addDependency("D", "C")

    var results = dag.execute()

    TestRunner.assertEqual(4, executionTrace.count)
    TestRunner.assertEqual("A", executionTrace[0])
    TestRunner.assertTrue((executionTrace[1] == "B" && executionTrace[2] == "C") || (executionTrace[1] == "C" && executionTrace[2] == "B"))
    TestRunner.assertEqual("D", executionTrace[3])

    // Verify values: A=10, B=20, C=15, D=35
    TestRunner.assertEqual(10, results["A"])
    TestRunner.assertEqual(20, results["B"])
    TestRunner.assertEqual(15, results["C"])
    TestRunner.assertEqual(35, results["D"])
  })

  TestRunner.test("circular dependency triggers cycle detection", Fn.new {
    var cyclicDag = Dag.new()
    cyclicDag.addNode("X", Fn.new { |deps| 1 })
    cyclicDag.addNode("Y", Fn.new { |deps| 2 })

    cyclicDag.addDependency("X", "Y")
    cyclicDag.addDependency("Y", "X") // Cycle!

    TestRunner.assertThrows(Fn.new {
      cyclicDag.execute()
    }, "Cyclic graph must abort with cycle error")
  })

  TestRunner.test("joinAll barrier waits for all branches", Fn.new {
    var tasks = [
      Fn.new { 10 },
      Fn.new { 20 },
      Fn.new { 30 }
    ]

    var results = Dag.joinAll(tasks)
    TestRunner.assertEqual(3, results.count)
    TestRunner.assertEqual(10, results[0])
    TestRunner.assertEqual(20, results[1])
    TestRunner.assertEqual(30, results[2])
  })

  TestRunner.test("joinAny barrier returns first successful result", Fn.new {
    var tasks = [
      Fn.new { Fiber.abort("fast fail") },
      Fn.new { "winner" },
      Fn.new { "backup" }
    ]

    var result = Dag.joinAny(tasks)
    TestRunner.assertEqual("winner", result)
  })

  TestRunner.test("joinQuorum barrier succeeds when quorum threshold met", Fn.new {
    var tasks = [
      Fn.new { "replica-1" },
      Fn.new { Fiber.abort("node down") },
      Fn.new { "replica-3" }
    ]

    var quorum = Dag.joinQuorum(tasks, 2)
    TestRunner.assertEqual(2, quorum.count)
    TestRunner.assertEqual("replica-1", quorum[0])
    TestRunner.assertEqual("replica-3", quorum[1])
  })
})
