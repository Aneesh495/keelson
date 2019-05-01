// Workflow state snapshotter and serialization for log compaction.
// Captures point-in-time workflow state to bound replay recovery time.

import "../core/json" for Json

class WorkflowSnapshot {
  construct new(workflowId, snapshotIndex, state, context, timestamp) {
    _workflowId = workflowId
    _snapshotIndex = snapshotIndex
    _state = state
    _context = (context != null) ? context : {}
    _timestamp = timestamp
  }

  workflowId { _workflowId }
  snapshotIndex { _snapshotIndex }
  state { _state }
  context { _context }
  timestamp { _timestamp }

  toMap() {
    return {
      "workflowId": _workflowId,
      "snapshotIndex": _snapshotIndex,
      "state": _state,
      "context": _context,
      "timestamp": _timestamp
    }
  }

  static fromMap(map) {
    return WorkflowSnapshot.new(
      map["workflowId"],
      map["snapshotIndex"],
      map["state"],
      map["context"],
      map["timestamp"]
    )
  }

  toJson() {
    return Json.stringify(toMap())
  }

  static fromJson(jsonStr) {
    var map = Json.parse(jsonStr)
    return fromMap(map)
  }
}
