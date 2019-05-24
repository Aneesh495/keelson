// Integration tests for fault-tolerant distributed ETL data pipeline.

import "../test_framework" for TestRunner
import "../../src/wren/workflows/etl_data_pipeline" for EtlPipelineWorkflow
import "../../src/wren/core/saga" for SagaStatus

TestRunner.describe("Distributed ETL Data Pipeline Saga", Fn.new {
  TestRunner.test("clean data batch processes through extraction to catalog publish", Fn.new {
    var wf = EtlPipelineWorkflow.new("etl-job-101")
    var spec = {
      "datasetId": "telemetry_events",
      "partitionDate": "2026-11-22",
      "recordCount": 10000,
      "strictSchema": true,
      "corruptRecordCount": 0
    }

    var result = wf.execute(spec)

    TestRunner.assertEqual("ETL_COMPLETED", result["status"])
    TestRunner.assertEqual("telemetry_events", result["datasetId"])
    TestRunner.assertEqual("2026-11-22", result["partitionDate"])
    TestRunner.assertEqual(9500, result["recordsLoaded"])
  })

  TestRunner.test("corrupted batch fails schema validation and purges source cache", Fn.new {
    var wf = EtlPipelineWorkflow.new("etl-job-corrupted")
    var corruptSpec = {
      "datasetId": "financial_trades",
      "partitionDate": "2026-11-21",
      "recordCount": 5000,
      "strictSchema": true,
      "corruptRecordCount": 142 // Schema violation!
    }

    var result = wf.execute(corruptSpec)

    TestRunner.assertEqual("ETL_PIPELINE_FAILED_AND_COMPENSATED", result["status"])

    var audit = result["rollbackAudit"]
    TestRunner.assertEqual(1, audit.count)
    TestRunner.assertEqual("purge_source_extract_cache:batch-financial_trades-2026-11-21", audit[0])

    TestRunner.assertEqual(SagaStatus.COMPENSATED, wf.saga.status)
  })
})
