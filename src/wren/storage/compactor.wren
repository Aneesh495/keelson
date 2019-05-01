// Event log compactor for Keelson.
// Periodically snapshots workflow state and truncates antecedent event log segments.

import "./snapshot" for WorkflowSnapshot
import "../core/event_log" for EventLog

class LogCompactor {
  construct new(snapshotIntervalEvents) {
    _snapshotInterval = (snapshotIntervalEvents != null) ? snapshotIntervalEvents : 50
    _snapshots = {}
  }

  snapshotInterval { _snapshotInterval }

  // Determines whether a workflow log has accumulated enough events to warrant snapshotting.
  shouldSnapshot(eventLog) {
    return eventLog.count >= _snapshotInterval
  }

  // Creates and records a snapshot, returning the compacted snapshot instance.
  createSnapshot(workflow, snapshotIndex, timestamp) {
    var snapshot = WorkflowSnapshot.new(
      workflow.id,
      snapshotIndex,
      workflow.status,
      workflow.context,
      timestamp
    )
    _snapshots[workflow.id] = snapshot
    return snapshot
  }

  getSnapshot(workflowId) {
    if (_snapshots.containsKey(workflowId)) {
      return _snapshots[workflowId]
    }
    return null
  }

  // Compacts an event log by trimming events preceding the snapshot boundary.
  compact(eventLog, snapshot) {
    var remainingEvents = []
    for (event in eventLog.events) {
      if (event.eventId > snapshot.snapshotIndex) {
        remainingEvents.add(event)
      }
    }

    var compactedLog = EventLog.new(eventLog.workflowId)
    for (e in remainingEvents) {
      compactedLog.addRestoredEvent(e)
    }

    return compactedLog
  }
}
