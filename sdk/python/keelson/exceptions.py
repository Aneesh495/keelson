"""
Keelson Client Exception Hierarchy
Structured exception classes for client communication and workflow execution failures.
"""

from typing import Optional


class KeelsonError(Exception):
    """Base exception for all Keelson client errors."""
    pass


class KeelsonConnectionError(KeelsonError):
    """Raised when communication with the Keelson daemon fails."""
    pass


class KeelsonAPIError(KeelsonError):
    """Raised when the engine daemon returns an HTTP error code."""
    def __init__(self, status_code: int, message: str, payload: Optional[dict] = None):
        super().__init__(f"HTTP {status_code}: {message}")
        self.status_code = status_code
        self.message = message
        self.payload = payload or {}


class WorkflowNotFoundError(KeelsonAPIError):
    """Raised when the requested workflow instance does not exist."""
    def __init__(self, workflow_id: str):
        super().__init__(404, f"Workflow '{workflow_id}' not found")
        self.workflow_id = workflow_id


class WorkflowExecutionError(KeelsonError):
    """Raised when a workflow terminates with an execution fault."""
    def __init__(self, workflow_id: str, error_details: str):
        super().__init__(f"Workflow '{workflow_id}' failed: {error_details}")
        self.workflow_id = workflow_id
        self.error_details = error_details
