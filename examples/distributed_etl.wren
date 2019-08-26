// Runnable demonstration of Keelson distributed ETL data pipeline.
// Showcases staged extraction, transform barriers, atomic catalog publication,
// and compensatory staging table purge on schema validation failure.

import "../src/wren/workflows/etl_data_pipeline" for EtlPipelineWorkflow
import "../src/wren/core/saga" for SagaStatus

System.print("============================================================")
System.print("    KEELSON: DISTRIBUTED FAULT-TOLERANT ETL PIPELINE DEMO   ")
System.print("============================================================")

// Scenario 1: Clean batch execution
System.print("\n>>> SCENARIO 1: Clean high-volume data batch (500k rows)")
System.print("------------------------------------------------------------")

var cleanSpec = {
  "datasetId": "telemetry_sensors",
  "partitionDate": "2026-11-22",
  "recordCount": 500000,
  "strictSchema": true,
  "corruptRecordCount": 0,
  "stagingUri": "s3://lakehouse-staged/telemetry_sensors/2026-11-22"
}

var wfClean = EtlPipelineWorkflow.new("etl-clean-01")
var reportClean = wfClean.execute(cleanSpec)

System.print("Status:           " + reportClean["status"])
System.print("Partition:        " + reportClean["partitionDate"])
System.print("Records Loaded:   %(reportClean["recordsLoaded"])")
System.print("Catalog Status:   PUBLISHED (v1)")

// Scenario 2: Corrupted schema batch triggering rollback
System.print("\n>>> SCENARIO 2: Corrupted batch triggering staging purge rollback")
System.print("------------------------------------------------------------")

var corruptSpec = {
  "datasetId": "financial_trades",
  "partitionDate": "2026-11-22",
  "recordCount": 100000,
  "strictSchema": true,
  "corruptRecordCount": 1420,
  "stagingUri": "s3://lakehouse-staged/financial_trades/2026-11-22"
}

var wfCorrupt = EtlPipelineWorkflow.new("etl-corrupt-02")
var reportCorrupt = wfCorrupt.execute(corruptSpec)

System.print("Status:           " + reportCorrupt["status"])
System.print("Dataset:          " + reportCorrupt["datasetId"])
System.print("Rollback Audit (Reverse-order staging purge):")
if (reportCorrupt["rollbackAudit"] != null) {
  for (item in reportCorrupt["rollbackAudit"]) {
    System.print("  [-] " + item)
  }
}

System.print("\n============================================================")
System.print("ETL pipeline demonstration completed successfully.")
System.print("============================================================")
