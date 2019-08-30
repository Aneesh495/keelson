// Runnable demonstration of Keelson staged IoT fleet firmware rollout.
// Demonstrates multi-stage canary gates (1 percent, 10 percent, 100 percent)
// with automated reverse-rollback when telemetry thresholds are violated.

import "../src/wren/workflows/firmware_rollout_canary" for FirmwareRolloutWorkflow
import "../src/wren/core/saga" for SagaStatus

System.print("============================================================")
System.print("   KEELSON: IOT FLEET FIRMWARE ROLLOUT CANARY DEMO          ")
System.print("============================================================")

// Scenario 1: Clean progressive rollout
System.print("\n>>> SCENARIO 1: Healthy progressive fleet deployment (10,000 devices)")
System.print("------------------------------------------------------------")

var healthyConfig = {
  "targetVersion": "2.4.1",
  "previousVersion": "2.3.9",
  "totalFleetSize": 10000,
  "canaryErrorRate": 0.002,
  "fleetWideErrorRate": 0.001
}

var wfHealthy = FirmwareRolloutWorkflow.new("rollout-healthy-01")
var reportHealthy = wfHealthy.execute(healthyConfig)

System.print("Status:           " + reportHealthy["status"])
System.print("Target Version:   v" + reportHealthy["targetVersion"])
System.print("Fleet Deployed:   %(reportHealthy["devicesUpdated"]) / %(reportHealthy["fleetSize"]) units")
System.print("Telemetry Gate:   PASSED (Error rate 0.2 percent < 2.0 percent)")

// Scenario 2: Telemetry anomaly triggering automated fleet rollback
System.print("\n>>> SCENARIO 2: Anomaly in stage 1 canary triggering rollback")
System.print("------------------------------------------------------------")

var anomalousConfig = {
  "targetVersion": "2.5.0-rc1",
  "previousVersion": "2.4.1",
  "totalFleetSize": 10000,
  "canaryErrorRate": 0.085, // 8.5% error rate trips canary gate
  "fleetWideErrorRate": 0.0
}

var wfAnomalous = FirmwareRolloutWorkflow.new("rollout-anomaly-02")
var reportAnomalous = wfAnomalous.execute(anomalousConfig)

System.print("Status:           " + reportAnomalous["status"])
System.print("Target Version:   v" + reportAnomalous["targetVersion"])
System.print("Restored Version: v" + reportAnomalous["restoredVersion"])
System.print("Rollback Audit (Fleet restored to stable baseline):")
if (reportAnomalous["rollbackAudit"] != null) {
  for (item in reportAnomalous["rollbackAudit"]) {
    System.print("  [-] " + item)
  }
}

System.print("\n============================================================")
System.print("Firmware rollout canary demonstration completed.")
System.print("============================================================")
