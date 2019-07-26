"""
Keelson Testing Harness and Mock Client
Provides in-memory simulation of the Keelson engine for fast unit and integration testing.
"""

import time
from typing import Any, Callable, Dict, List, Optional

from keelson.client import KeelsonClient
from keelson.exceptions import WorkflowNotFoundError
from keelson.models import (
    EngineHealth,
    EventRecord,
    QueryResponse,
    WorkflowInstance,
    WorkflowStatus,
)


class MockKeelsonClient(KeelsonClient):
    """In-memory simulation of KeelsonClient for zero-dependency test suites."""

    def __init__(self):
        super().__init__(endpoint="http://mock-keelson:8080")
        self._workflows: Dict[str, WorkflowInstance] = {}
        self._events: Dict[str, List[EventRecord]] = {}
        self._signals: Dict[str, List[Dict[str, Any]]] = {}
        self._queries: Dict[str, Callable[[str, Dict[str, Any]], Any]] = {}
        self._event_counter = 0
        self._fault_injections: Dict[str, Exception] = {}

    def inject_fault(self, method_name: str, exception: Exception):
        """Configure a synthetic failure for chaos and resilience testing."""
        self._fault_injections[method_name] = exception

    def clear_faults(self):
        """Remove all active fault injection triggers."""
        self._fault_injections.clear()

    def _check_fault(self, method_name: str):
        if method_name in self._fault_injections:
            raise self._fault_injections[method_name]

    def register_query_handler(self, query_type: str, handler: Callable[[str, Dict[str, Any]], Any]):
        """Register a mock query responder."""
        self._queries[query_type] = handler

    def health(self) -> EngineHealth:
        self._check_fault("health")
        return EngineHealth(
            status="healthy",
            version="1.0.0-mock",
            uptime_seconds=42.0,
            active_fibers=len([w for w in self._workflows.values() if w.status == WorkflowStatus.RUNNING]),
            total_events=self._event_counter,
        )

    def metrics(self) -> str:
        self._check_fault("metrics")
        return (
            "# HELP keelson_workflows_total Total workflows created\n"
            "# TYPE keelson_workflows_total counter\n"
            f"keelson_workflows_total {len(self._workflows)}\n"
        )

    def start_workflow(
        self,
        workflow_type: str,
        input_data: Optional[Dict[str, Any]] = None,
        workflow_id: Optional[str] = None,
    ) -> WorkflowInstance:
        self._check_fault("start_workflow")
        wf_id = workflow_id or f"wf-mock-{len(self._workflows) + 1}"
        now_ns = time.time_ns()

        wf = WorkflowInstance(
            workflow_id=wf_id,
            workflow_type=workflow_type,
            status=WorkflowStatus.RUNNING,
            start_time_ns=now_ns,
            metadata={"input": input_data or {}},
        )
        self._workflows[wf_id] = wf
        self._events[wf_id] = []

        self._record_event(wf_id, "WORKFLOW_STARTED", {"type": workflow_type, "input": input_data or {}})
        return wf

    def get_workflow(self, workflow_id: str) -> WorkflowInstance:
        self._check_fault("get_workflow")
        if workflow_id not in self._workflows:
            raise WorkflowNotFoundError(workflow_id)
        return self._workflows[workflow_id]

    def complete_workflow(self, workflow_id: str, result: Any):
        """Simulate successful workflow termination."""
        wf = self.get_workflow(workflow_id)
        wf.status = WorkflowStatus.COMPLETED
        wf.result = result
        wf.end_time_ns = time.time_ns()
        self._record_event(workflow_id, "WORKFLOW_COMPLETED", {"result": result})

    def fail_workflow(self, workflow_id: str, error: str):
        """Simulate workflow execution failure."""
        wf = self.get_workflow(workflow_id)
        wf.status = WorkflowStatus.FAILED
        wf.error = error
        wf.end_time_ns = time.time_ns()
        self._record_event(workflow_id, "WORKFLOW_FAILED", {"error": error})

    def send_signal(self, workflow_id: str, channel: str, data: Any) -> bool:
        self._check_fault("send_signal")
        if workflow_id not in self._workflows:
            raise WorkflowNotFoundError(workflow_id)

        if workflow_id not in self._signals:
            self._signals[workflow_id] = []

        signal_payload = {"channel": channel, "data": data, "timestamp_ns": time.time_ns()}
        self._signals[workflow_id].append(signal_payload)
        self._record_event(workflow_id, "SIGNAL_RECEIVED", signal_payload)
        return True

    def get_history(self, workflow_id: str) -> List[EventRecord]:
        self._check_fault("get_history")
        if workflow_id not in self._workflows:
            raise WorkflowNotFoundError(workflow_id)
        return list(self._events.get(workflow_id, []))

    def query(self, workflow_id: str, query_type: str, args: Optional[Dict[str, Any]] = None) -> QueryResponse:
        self._check_fault("query")
        if workflow_id not in self._workflows:
            raise WorkflowNotFoundError(workflow_id)

        if query_type in self._queries:
            res = self._queries[query_type](workflow_id, args or {})
        else:
            res = {"status": self._workflows[workflow_id].status.value}

        return QueryResponse(
            workflow_id=workflow_id,
            query_type=query_type,
            result=res,
            execution_time_ms=0.15,
        )

    def _record_event(self, workflow_id: str, event_type: str, payload: Dict[str, Any]):
        self._event_counter += 1
        record = EventRecord(
            event_id=self._event_counter,
            event_type=event_type,
            timestamp_ns=time.time_ns(),
            workflow_id=workflow_id,
            payload=payload,
        )
        self._events[workflow_id].append(record)
