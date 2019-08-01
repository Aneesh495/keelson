"""
Unit tests for the Keelson Python SDK.
"""

import unittest
from keelson.exceptions import (
    KeelsonAPIError,
    KeelsonConnectionError,
    WorkflowNotFoundError,
)
from keelson.models import (
    EngineHealth,
    EventRecord,
    QueryResponse,
    SagaReport,
    SagaStep,
    WorkflowInstance,
    WorkflowStatus,
)
from keelson.testing import MockKeelsonClient


class TestKeelsonModels(unittest.TestCase):
    def test_workflow_instance_roundtrip(self):
        wf = WorkflowInstance(
            workflow_id="wf-101",
            workflow_type="order_saga",
            status=WorkflowStatus.RUNNING,
            start_time_ns=1700000000000000,
            metadata={"user": "alice"},
        )
        d = wf.to_dict()
        self.assertEqual(d["workflow_id"], "wf-101")
        self.assertEqual(d["status"], "RUNNING")

        restored = WorkflowInstance.from_dict(d)
        self.assertEqual(restored.workflow_id, "wf-101")
        self.assertEqual(restored.status, WorkflowStatus.RUNNING)
        self.assertEqual(restored.metadata["user"], "alice")

    def test_event_record_roundtrip(self):
        rec = EventRecord(
            event_id=42,
            event_type="ACTIVITY_COMPLETED",
            timestamp_ns=1700000001000000,
            workflow_id="wf-101",
            payload={"step": "charge_card", "amount": 9900},
        )
        d = rec.to_dict()
        self.assertEqual(d["event_id"], 42)
        restored = EventRecord.from_dict(d)
        self.assertEqual(restored.event_id, 42)
        self.assertEqual(restored.payload["amount"], 9900)

    def test_saga_report_parsing(self):
        raw = {
            "workflow_id": "wf-saga-99",
            "overall_status": "COMPENSATED",
            "steps": [
                {
                    "name": "reserve_stock",
                    "status": "COMPENSATED",
                    "forward_result": {"reserved": True},
                    "compensation_result": {"released": True},
                },
                {
                    "name": "charge_card",
                    "status": "FAILED",
                    "error": "insufficient_funds",
                },
            ],
            "compensation_order": ["reserve_stock"],
            "audit_trail": ["reserve_stock:done", "charge_card:fail", "reserve_stock:reverted"],
        }
        report = SagaReport.from_dict(raw)
        self.assertEqual(report.workflow_id, "wf-saga-99")
        self.assertEqual(len(report.steps), 2)
        self.assertEqual(report.steps[0].name, "reserve_stock")
        self.assertEqual(report.compensation_order, ["reserve_stock"])


class TestMockKeelsonClient(unittest.TestCase):
    def setUp(self):
        self.client = MockKeelsonClient()

    def test_health_and_metrics(self):
        health = self.client.health()
        self.assertEqual(health.status, "healthy")
        self.assertEqual(health.version, "1.0.0-mock")

        metrics_text = self.client.metrics()
        self.assertIn("keelson_workflows_total", metrics_text)

    def test_workflow_lifecycle(self):
        wf = self.client.start_workflow(
            workflow_type="data_sync",
            input_data={"partition": 7},
            workflow_id="wf-custom-1",
        )
        self.assertEqual(wf.workflow_id, "wf-custom-1")
        self.assertEqual(wf.status, WorkflowStatus.RUNNING)

        fetched = self.client.get_workflow("wf-custom-1")
        self.assertEqual(fetched.workflow_id, "wf-custom-1")

        # Complete workflow
        self.client.complete_workflow("wf-custom-1", result={"rows_synced": 45000})
        done_wf = self.client.get_workflow("wf-custom-1")
        self.assertEqual(done_wf.status, WorkflowStatus.COMPLETED)
        self.assertEqual(done_wf.result["rows_synced"], 45000)

        # Check history
        history = self.client.get_history("wf-custom-1")
        self.assertEqual(len(history), 2)
        self.assertEqual(history[0].event_type, "WORKFLOW_STARTED")
        self.assertEqual(history[1].event_type, "WORKFLOW_COMPLETED")

    def test_signal_dispatch(self):
        self.client.start_workflow("approval_flow", workflow_id="wf-approval-1")
        ok = self.client.send_signal("wf-approval-1", "user_approval", {"approved": True, "by": "bob"})
        self.assertTrue(ok)

        history = self.client.get_history("wf-approval-1")
        self.assertEqual(len(history), 2)
        self.assertEqual(history[1].event_type, "SIGNAL_RECEIVED")
        self.assertEqual(history[1].payload["channel"], "user_approval")

    def test_query_dispatch(self):
        self.client.start_workflow("query_test", workflow_id="wf-query-1")
        self.client.register_query_handler("get_progress", lambda wf_id, args: {"percent": 75})

        resp = self.client.query("wf-query-1", "get_progress")
        self.assertEqual(resp.workflow_id, "wf-query-1")
        self.assertEqual(resp.result["percent"], 75)

    def test_workflow_not_found_error(self):
        with self.assertRaises(WorkflowNotFoundError):
            self.client.get_workflow("non-existent-wf")

    def test_fault_injection(self):
        self.client.inject_fault("start_workflow", KeelsonConnectionError("network partition"))
        with self.assertRaises(KeelsonConnectionError):
            self.client.start_workflow("test")

        self.client.clear_faults()
        wf = self.client.start_workflow("test")
        self.assertIsNotNone(wf)


if __name__ == "__main__":
    unittest.main()
