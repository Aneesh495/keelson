"""
Keelson Data Models
Typed data structures representing workflows, event logs, sagas, and engine state.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class WorkflowStatus(str, Enum):
    """Execution status lifecycle for a durable workflow."""
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    COMPENSATED = "COMPENSATED"
    CANCELLED = "CANCELLED"


@dataclass
class WorkflowInstance:
    """Represents the execution state of a durable workflow instance."""
    workflow_id: str
    workflow_type: str
    status: WorkflowStatus
    start_time_ns: int = 0
    end_time_ns: int = 0
    result: Optional[Any] = None
    error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "WorkflowInstance":
        """Deserialize from dictionary representation."""
        status_val = data.get("status", "PENDING")
        if isinstance(status_val, str):
            status = WorkflowStatus(status_val)
        else:
            status = status_val

        return cls(
            workflow_id=data["workflow_id"],
            workflow_type=data.get("workflow_type", "generic"),
            status=status,
            start_time_ns=data.get("start_time_ns", 0),
            end_time_ns=data.get("end_time_ns", 0),
            result=data.get("result"),
            error=data.get("error"),
            metadata=data.get("metadata", {}),
        )

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary representation."""
        return {
            "workflow_id": self.workflow_id,
            "workflow_type": self.workflow_type,
            "status": self.status.value if isinstance(self.status, WorkflowStatus) else str(self.status),
            "start_time_ns": self.start_time_ns,
            "end_time_ns": self.end_time_ns,
            "result": self.result,
            "error": self.error,
            "metadata": self.metadata,
        }


@dataclass
class EventRecord:
    """An immutable journal entry in the append-only event source."""
    event_id: int
    event_type: str
    timestamp_ns: int
    workflow_id: str
    payload: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "EventRecord":
        """Deserialize from dictionary representation."""
        return cls(
            event_id=data.get("event_id", 0),
            event_type=data.get("event_type", "UNKNOWN"),
            timestamp_ns=data.get("timestamp_ns", 0),
            workflow_id=data.get("workflow_id", ""),
            payload=data.get("payload", {}),
        )

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary representation."""
        return {
            "event_id": self.event_id,
            "event_type": self.event_type,
            "timestamp_ns": self.timestamp_ns,
            "workflow_id": self.workflow_id,
            "payload": self.payload,
        }


@dataclass
class SagaStep:
    """A discrete unit of work with forward activity and backward compensation."""
    name: str
    status: str
    forward_result: Optional[Any] = None
    compensation_result: Optional[Any] = None
    error: Optional[str] = None


@dataclass
class SagaReport:
    """Execution summary of a distributed saga."""
    workflow_id: str
    overall_status: str
    steps: List[SagaStep] = field(default_factory=list)
    compensation_order: List[str] = field(default_factory=list)
    audit_trail: List[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "SagaReport":
        """Deserialize from dictionary representation."""
        raw_steps = data.get("steps", [])
        parsed_steps = []
        for s in raw_steps:
            if isinstance(s, dict):
                parsed_steps.append(SagaStep(
                    name=s.get("name", ""),
                    status=s.get("status", ""),
                    forward_result=s.get("forward_result"),
                    compensation_result=s.get("compensation_result"),
                    error=s.get("error"),
                ))
            else:
                parsed_steps.append(s)

        return cls(
            workflow_id=data.get("workflow_id", ""),
            overall_status=data.get("overall_status", "UNKNOWN"),
            steps=parsed_steps,
            compensation_order=data.get("compensation_order", []),
            audit_trail=data.get("audit_trail", []),
        )


@dataclass
class QueryResponse:
    """Result of an asynchronous read-only query dispatch."""
    workflow_id: str
    query_type: str
    result: Any
    execution_time_ms: float = 0.0


@dataclass
class EngineHealth:
    """Health check diagnostics from the Keelson HTTP daemon."""
    status: str
    version: str
    uptime_seconds: float = 0.0
    active_fibers: int = 0
    total_events: int = 0
