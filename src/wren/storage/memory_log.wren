// In-memory event log storage implementation.
// High-performance store for ephemeral workflows, unit testing, and benchmarking.

import "../core/event_log" for EventLog

class MemoryLogStorage {
  construct new() {
    _logs = {}
  }

  // Retrieves or creates an EventLog for a specific workflow ID.
  getOrCreate(workflowId) {
    if (!_logs.containsKey(workflowId)) {
      _logs[workflowId] = EventLog.new(workflowId)
    }
    return _logs[workflowId]
  }

  // Appends a single history event to the in-memory log.
  appendEvent(event) {
    var log = getOrCreate(event.workflowId)
    log.addRestoredEvent(event)
  }

  has(workflowId) {
    return _logs.containsKey(workflowId)
  }

  delete(workflowId) {
    _logs.remove(workflowId)
  }

  count { _logs.count }

  clear() {
    _logs.clear()
  }
}
