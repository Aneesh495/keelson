// Fault-tolerant distributed ETL data pipeline saga for Keelson.
// Coordinates source batch extraction, schema validation, deduplication,
// transformation, staged warehouse loading, and atomic catalog publication.

import "../core/saga" for Saga, SagaStatus
import "../core/workflow" for Workflow

class EtlPipelineWorkflow is Workflow {
  construct new(id) {
    super(id)
    _saga = Saga.new(id)
  }

  saga { _saga }

  execute(jobSpec) {
    var rollbackAudit = []
    var datasetId = jobSpec["datasetId"]
    var partitionDate = jobSpec["partitionDate"]

    setContext("datasetId", datasetId)
    setContext("partitionDate", partitionDate)

    // Stage 1: Extract partition batch from source
    _saga.addStep("extract_batch", Fn.new { |ctx|
      return {
        "batchId": "batch-" + datasetId + "-" + partitionDate,
        "rawRecordCount": jobSpec["recordCount"],
        "sourceUri": "s3://lakehouse-raw/" + datasetId + "/" + partitionDate
      }
    }, Fn.new { |res, ctx|
      rollbackAudit.add("purge_source_extract_cache:" + res["batchId"])
    })

    // Stage 2: Validate schema conformance
    _saga.addStep("validate_schema", Fn.new { |ctx|
      var enforceStrict = jobSpec["strictSchema"]
      var corruptRecords = jobSpec["corruptRecordCount"]

      if (enforceStrict != null && enforceStrict == true && corruptRecords > 0) {
        Fiber.abort("Schema validation failed: " + corruptRecords.toString + " corrupt records detected")
      }

      return {
        "valid": true,
        "schemaVersion": "v3"
      }
    }, null)

    // Stage 3: Deduplicate records
    _saga.addStep("deduplicate_records", Fn.new { |ctx|
      var extract = ctx["extract_batch"]
      var deduped = (extract["rawRecordCount"] * 0.95).floor
      return {
        "dedupedCount": deduped,
        "duplicatesRemoved": extract["rawRecordCount"] - deduped
      }
    }, null)

    // Stage 4: Stage warehouse loading into isolated temporary partition
    _saga.addStep("stage_warehouse_load", Fn.new { |ctx|
      var dedup = ctx["deduplicate_records"]
      var stagingTable = "tmp_staging_" + datasetId + "_" + partitionDate.replace("-", "_")
      return {
        "stagingTable": stagingTable,
        "loadedRows": dedup["dedupedCount"]
      }
    }, Fn.new { |res, ctx|
      rollbackAudit.add("drop_staging_table:" + res["stagingTable"])
    })

    // Stage 5: Atomic metadata swap and catalog publish
    _saga.addStep("publish_catalog_pointer", Fn.new { |ctx|
      var stage = ctx["stage_warehouse_load"]
      return {
        "publishedTable": datasetId,
        "partition": partitionDate,
        "version": 42
      }
    }, Fn.new { |res, ctx|
      rollbackAudit.add("revert_catalog_pointer:" + res["publishedTable"])
    })

    var success = _saga.execute()
    setContext("rollbackAudit", rollbackAudit)

    if (!success) {
      return {
        "status": "ETL_PIPELINE_FAILED_AND_COMPENSATED",
        "datasetId": datasetId,
        "partitionDate": partitionDate,
        "rollbackAudit": rollbackAudit
      }
    }

    return {
      "status": "ETL_COMPLETED",
      "datasetId": datasetId,
      "partitionDate": partitionDate,
      "recordsLoaded": _saga.results["stage_warehouse_load"]["loadedRows"]
    }
  }
}
