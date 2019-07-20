"""
Keelson REST Client
Synchronous HTTP client for interacting with the Keelson execution engine daemon.
"""

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

from keelson.exceptions import (
    KeelsonAPIError,
    KeelsonConnectionError,
    WorkflowNotFoundError,
)
from keelson.models import (
    EngineHealth,
    EventRecord,
    QueryResponse,
    WorkflowInstance,
    WorkflowStatus,
)


class KeelsonClient:
    """Client for dispatching workflows, signals, and queries to Keelson."""

    def __init__(self, endpoint: str = "http://127.0.0.1:8080", timeout: float = 10.0):
        self.endpoint = endpoint.rstrip("/")
        self.timeout = timeout

    def _request(
        self,
        method: str,
        path: str,
        body: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Any:
        url = f"{self.endpoint}{path}"
        if params:
            query_str = urllib.parse.urlencode(params)
            url = f"{url}?{query_str}"

        headers = {
            "Accept": "application/json",
            "User-Agent": "Keelson-Python-SDK/1.0.0",
        }

        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode("utf-8")

        req = urllib.request.Request(url, data=data, headers=headers, method=method)

        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                content_type = response.headers.get("Content-Type", "")
                raw_body = response.read().decode("utf-8")
                if "application/json" in content_type:
                    return json.loads(raw_body)
                return raw_body
        except urllib.error.HTTPError as err:
            err_body = err.read().decode("utf-8")
            parsed_err = {}
            try:
                parsed_err = json.loads(err_body)
            except Exception:
                parsed_err = {"raw": err_body}

            if err.code == 404:
                raise WorkflowNotFoundError(path.split("/")[-1])
            raise KeelsonAPIError(err.code, parsed_err.get("error", err.reason), parsed_err)
        except urllib.error.URLError as err:
            raise KeelsonConnectionError(f"Could not connect to Keelson daemon at {self.endpoint}: {err.reason}")

    def health(self) -> EngineHealth:
        """Inspect engine daemon health and operational status."""
        data = self._request("GET", "/health")
        return EngineHealth(
            status=data.get("status", "unknown"),
            version=data.get("version", "unknown"),
            uptime_seconds=float(data.get("uptime_seconds", 0.0)),
            active_fibers=int(data.get("active_fibers", 0)),
            total_events=int(data.get("total_events", 0)),
        )

    def metrics(self) -> str:
        """Fetch raw Prometheus exposition metrics from the daemon."""
        return self._request("GET", "/metrics")

    def start_workflow(
        self,
        workflow_type: str,
        input_data: Optional[Dict[str, Any]] = None,
        workflow_id: Optional[str] = None,
    ) -> WorkflowInstance:
        """Dispatch a new durable workflow for execution."""
        payload = {
            "workflow_type": workflow_type,
            "input": input_data or {},
        }
        if workflow_id:
            payload["workflow_id"] = workflow_id

        resp = self._request("POST", "/api/v1/workflows", body=payload)
        return WorkflowInstance.from_dict(resp)

    def get_workflow(self, workflow_id: str) -> WorkflowInstance:
        """Retrieve current status and metadata of a workflow instance."""
        resp = self._request("GET", f"/api/v1/workflows/{workflow_id}")
        return WorkflowInstance.from_dict(resp)

    def send_signal(self, workflow_id: str, channel: str, data: Any) -> bool:
        """Send an asynchronous signal to a waiting workflow mailbox."""
        payload = {
            "channel": channel,
            "data": data,
            "timestamp_ns": time.time_ns(),
        }
        resp = self._request("POST", f"/api/v1/workflows/{workflow_id}/signals", body=payload)
        return resp.get("status") == "accepted"

    def get_history(self, workflow_id: str) -> List[EventRecord]:
        """Fetch the immutable event sourcing journal for a workflow."""
        resp = self._request("GET", f"/api/v1/workflows/{workflow_id}/events")
        records = []
        for item in resp.get("events", []):
            records.append(EventRecord.from_dict(item))
        return records

    def query(self, workflow_id: str, query_type: str, args: Optional[Dict[str, Any]] = None) -> QueryResponse:
        """Execute a read-only query against workflow state without side effects."""
        payload = {
            "query_type": query_type,
            "args": args or {},
        }
        t0 = time.perf_counter()
        resp = self._request("POST", f"/api/v1/workflows/{workflow_id}/queries", body=payload)
        duration_ms = (time.perf_counter() - t0) * 1000.0

        return QueryResponse(
            workflow_id=workflow_id,
            query_type=query_type,
            result=resp.get("result"),
            execution_time_ms=duration_ms,
        )

    def wait_for_completion(
        self,
        workflow_id: str,
        poll_interval: float = 0.5,
        max_wait_seconds: float = 30.0,
    ) -> WorkflowInstance:
        """Block until workflow terminates (COMPLETED, FAILED, COMPENSATED, CANCELLED)."""
        deadline = time.time() + max_wait_seconds
        while time.time() < deadline:
            wf = self.get_workflow(workflow_id)
            if wf.status in (
                WorkflowStatus.COMPLETED,
                WorkflowStatus.FAILED,
                WorkflowStatus.COMPENSATED,
                WorkflowStatus.CANCELLED,
            ):
                return wf
            time.sleep(poll_interval)

        raise TimeoutError(f"Workflow '{workflow_id}' did not complete within {max_wait_seconds}s")
