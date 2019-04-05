// Unit tests for Keelson QueryRegistry.

import "../test_framework" for TestRunner
import "../../src/wren/core/query" for QueryRegistry
import "../../src/wren/core/workflow" for Workflow

class SampleQueryWorkflow is Workflow {
  construct new(id) {
    super(id)
    setContext("processedCount", 42)
    setContext("status", "ACTIVE")
  }
}

TestRunner.describe("QueryRegistry Read-Only Inspection", Fn.new {
  TestRunner.test("dispatches query returning workflow state without side effects", Fn.new {
    var registry = QueryRegistry.new()
    var wf = SampleQueryWorkflow.new("q-wf-1")

    registry.register("get_stats", Fn.new { |workflow, args|
      return {
        "count": workflow.query("processedCount"),
        "status": workflow.query("status"),
        "extra": args["multiplier"] * 10
      }
    })

    var result = registry.dispatch(wf, "get_stats", {"multiplier": 3})
    TestRunner.assertEqual(42, result["count"])
    TestRunner.assertEqual("ACTIVE", result["status"])
    TestRunner.assertEqual(30, result["extra"])
  })

  TestRunner.test("unregistered query raises abort", Fn.new {
    var registry = QueryRegistry.new()
    var wf = SampleQueryWorkflow.new("q-wf-2")

    TestRunner.assertThrows(Fn.new {
      registry.dispatch(wf, "missing_query", {})
    }, "Unregistered query must throw abort")
  })
})
