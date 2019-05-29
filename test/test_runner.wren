// Master test runner for Keelson.
// Executes all unit, saga, replay, and integration test suites.

import "./test_framework" for TestRunner

System.print("============================================================")
System.print("             KEELSON TEST SUITE EXECUTION                   ")
System.print("============================================================")

// Core unit tests
import "./unit/test_priority_queue"
import "./unit/test_json"
import "./unit/test_state_machine"
import "./unit/test_fiber_pool"
import "./unit/test_retry_policy"
import "./unit/test_activity"
import "./unit/test_event_log"
import "./unit/test_storage"
import "./unit/test_timer"
import "./unit/test_signal"
import "./unit/test_query"
import "./unit/test_dag"
import "./unit/test_resilience"
import "./unit/test_idempotency"
import "./unit/test_cron"
import "./unit/test_metrics"
import "./unit/test_snapshot"

// Saga orchestration tests
import "./saga/test_saga_basic"
import "./saga/test_saga_nested"

// Replay engine and crash recovery tests
import "./replay/test_replay_basic"
import "./replay/test_replay_crash_recovery"

// Integration domain workflows
import "./integration/test_full_engine"
import "./integration/test_e_commerce_order"
import "./integration/test_cloud_provisioning"
import "./integration/test_firmware_rollout"
import "./integration/test_etl_pipeline"
import "./integration/test_approval_workflow"

var success = TestRunner.report()
if (!success) {
  Fiber.abort("Test suite encountered failures")
}
