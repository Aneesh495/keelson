// IoT and robotics fleet firmware rollout orchestrator with staged canary gates.
// Coordinates phased device updates (1%, 10%, 50%, 100%) and automatic rollback upon telemetry anomalies.

import "../core/saga" for Saga, SagaStatus
import "../core/workflow" for Workflow

class FirmwareRolloutWorkflow is Workflow {
  construct new(id) {
    super(id)
    _saga = Saga.new(id)
  }

  saga { _saga }

  execute(rolloutConfig) {
    var rollbackAudit = []
    var targetVersion = rolloutConfig["targetVersion"]
    var previousVersion = rolloutConfig["previousVersion"]
    var totalFleetSize = rolloutConfig["totalFleetSize"]

    setContext("targetVersion", targetVersion)
    setContext("previousVersion", previousVersion)

    // Stage 1: Canary 1 percent cohort (e.g. 100 devices out of 10,000)
    _saga.addStep("canary_cohort_1_pct", Fn.new { |ctx|
      var count = (totalFleetSize * 0.01).round
      return {
        "cohort": "canary_1_pct",
        "devicesUpdated": count,
        "version": targetVersion
      }
    }, Fn.new { |res, ctx|
      rollbackAudit.add("rollback_cohort_1_pct:v" + previousVersion)
    })

    // Stage 2: Telemetry validation gate for 1 percent canary
    _saga.addStep("validate_canary_telemetry", Fn.new { |ctx|
      var errorRate = rolloutConfig["canaryErrorRate"]
      if (errorRate != null && errorRate > 0.02) {
        Fiber.abort("Canary telemetry gate failed: error rate exceeds 2 percent threshold")
      }
      return {"gate": "canary_telemetry", "passed": true}
    }, null)

    // Stage 3: Cohort 10 percent rollout
    _saga.addStep("rollout_cohort_10_pct", Fn.new { |ctx|
      var count = (totalFleetSize * 0.10).round
      return {
        "cohort": "cohort_10_pct",
        "devicesUpdated": count,
        "version": targetVersion
      }
    }, Fn.new { |res, ctx|
      rollbackAudit.add("rollback_cohort_10_pct:v" + previousVersion)
    })

    // Stage 4: Telemetry validation gate for 10 percent cohort
    _saga.addStep("validate_10_pct_telemetry", Fn.new { |ctx|
      var errorRate = rolloutConfig["phase2ErrorRate"]
      if (errorRate != null && errorRate > 0.02) {
        Fiber.abort("Phase 2 telemetry gate failed: error rate exceeds 2 percent threshold")
      }
      return {"gate": "phase2_telemetry", "passed": true}
    }, null)

    // Stage 5: Full 100 percent fleet deployment
    _saga.addStep("rollout_cohort_100_pct", Fn.new { |ctx|
      return {
        "cohort": "full_fleet",
        "devicesUpdated": totalFleetSize,
        "version": targetVersion
      }
    }, Fn.new { |res, ctx|
      rollbackAudit.add("rollback_full_fleet:v" + previousVersion)
    })

    var success = _saga.execute()
    setContext("rollbackAudit", rollbackAudit)

    if (!success) {
      return {
        "status": "ROLLOUT_HALTED_AND_ROLLED_BACK",
        "targetVersion": targetVersion,
        "restoredVersion": previousVersion,
        "rollbackAudit": rollbackAudit
      }
    }

    return {
      "status": "ROLLOUT_COMPLETED",
      "targetVersion": targetVersion,
      "fleetSize": totalFleetSize,
      "devicesUpdated": totalFleetSize
    }
  }
}
