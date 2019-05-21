// Integration tests for staged IoT fleet firmware rollout and canary gates.

import "../test_framework" for TestRunner
import "../../src/wren/workflows/firmware_rollout_canary" for FirmwareRolloutWorkflow
import "../../src/wren/core/saga" for SagaStatus

TestRunner.describe("Fleet Firmware Rollout Canary Workflow", Fn.new {
  TestRunner.test("healthy firmware rollout completes all stages across fleet", Fn.new {
    var wf = FirmwareRolloutWorkflow.new("fw-rollout-v2-1")
    var config = {
      "targetVersion": "2.1.0",
      "previousVersion": "2.0.4",
      "totalFleetSize": 10000,
      "canaryErrorRate": 0.005, // 0.5% (healthy)
      "phase2ErrorRate": 0.008  // 0.8% (healthy)
    }

    var result = wf.execute(config)

    TestRunner.assertEqual("ROLLOUT_COMPLETED", result["status"])
    TestRunner.assertEqual("2.1.0", result["targetVersion"])
    TestRunner.assertEqual(10000, result["devicesUpdated"])
  })

  TestRunner.test("telemetry anomaly triggers immediate canary rollback", Fn.new {
    var wf = FirmwareRolloutWorkflow.new("fw-rollout-faulty")
    var faultyConfig = {
      "targetVersion": "3.0.0-rc1",
      "previousVersion": "2.9.9",
      "totalFleetSize": 5000,
      "canaryErrorRate": 0.005, // Canary passed
      "phase2ErrorRate": 0.085  // 8.5% error spike in 10% cohort! Trips gate!
    }

    var result = wf.execute(faultyConfig)

    TestRunner.assertEqual("ROLLOUT_HALTED_AND_ROLLED_BACK", result["status"])
    TestRunner.assertEqual("2.9.9", result["restoredVersion"])

    // Verify reverse rollback of cohorts:
    // 10% cohort rolled back first, then 1% canary rolled back
    var audit = result["rollbackAudit"]
    TestRunner.assertEqual(2, audit.count)
    TestRunner.assertEqual("rollback_cohort_10_pct:v2.9.9", audit[0])
    TestRunner.assertEqual("rollback_cohort_1_pct:v2.9.9", audit[1])

    TestRunner.assertEqual(SagaStatus.COMPENSATED, wf.saga.status)
  })
})
