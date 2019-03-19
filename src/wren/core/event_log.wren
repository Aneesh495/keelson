// Append-only event history log and event sourcing schema for Keelson workflows.
// Every state change, activity execution, timer, and signal is durably recorded.

import "./json" for Json

class EventType {
  static WORKFLOW_STARTED { "WorkflowExecutionStarted" }
  static WORKFLOW_COMPLETED { "WorkflowExecutionCompleted" }
  static WORKFLOW_FAILED { "WorkflowExecutionFailed" }
  static WORKFLOW_COMPENSATED { "WorkflowExecutionCompensated" }

  static ACTIVITY_SCHEDULED { "ActivityTaskScheduled" }
  static ACTIVITY_STARTED { "ActivityTaskStarted" }
  static ACTIVITY_COMPLETED { "ActivityTaskCompleted" }
  static ACTIVITY_FAILED { "ActivityTaskFailed" }
  static ACTIVITY_TIMED_OUT { "ActivityTaskTimedOut" }

  static TIMER_STARTED { "TimerStarted" }
  static TIMER_FIRED { "TimerFired" }
  static TIMER_CANCELLED { "TimerCancelled" }

  static SIGNAL_RECEIVED { "SignalReceived" }
  static QUERY_RECORDED { "QueryRecorded" }
}

class HistoryEvent {
  construct new(eventId, workflowId, eventType, timestamp, attributes) {
    _eventId = eventId
    _workflowId = workflowId
    _eventType = eventType
    _timestamp = timestamp
    _attributes = (attributes != null) ? attributes : {}
  }

  eventId { _eventId }
  workflowId { _workflowId }
  eventType { _eventType }
  timestamp { _timestamp }
  attributes { _attributes }

  // Serializes this event to a JSON-compatible map.
  toMap() {
    return {
      "eventId": _eventId,
      "workflowId": _workflowId,
      "eventType": _eventType,
      "timestamp": _timestamp,
      "attributes": _attributes
    }
  }

  // Deserializes an event from a map representation.
  static fromMap(map) {
    return HistoryEvent.new(
      map["eventId"],
      map["workflowId"],
      map["eventType"],
      map["timestamp"],
      map["attributes"]
    )
  }

  toString {
    return "Event(" + _eventId.toString + ":" + _eventType + " for " + _workflowId + ")"
  }
}

class EventLog {
  construct new(workflowId) {
    _workflowId = workflowId
    _events = []
    _nextEventId = 1
  }

  workflowId { _workflowId }
  events { _events }
  count { _events.count }
  isEmpty { _events.count == 0 }

  // Appends a new event to the end of the history stream.
  append(eventType, timestamp, attributes) {
    var event = HistoryEvent.new(_nextEventId, _workflowId, eventType, timestamp, attributes)
    _events.add(event)
    _nextEventId = _nextEventId + 1
    return event
  }

  // Restores a previously persisted event during rehydration.
  addRestoredEvent(event) {
    _events.add(event)
    if (event.eventId >= _nextEventId) {
      _nextEventId = event.eventId + 1
    }
  }

  // Returns the event at the specified index.
  [index] { _events[index] }

  // Finds all events matching a specific event type.
  findEvents(type) {
    var matches = []
    for (event in _events) {
      if (event.eventType == type) {
        matches.add(event)
      }
    }
    return matches
  }

  // Finds the most recent event matching a specific type.
  findLast(type) {
    var i = _events.count - 1
    while (i >= 0) {
      if (_events[i].eventType == type) {
        return _events[i]
      }
      i = i - 1
    }
    return null
  }

  // Serializes the entire event history to a JSON string.
  toJson() {
    var list = []
    for (e in _events) {
      list.add(e.toMap())
    }
    return Json.stringify(list)
  }

  // Deserializes and rehydrates an event log from a JSON string.
  static fromJson(workflowId, jsonString) {
    var log = EventLog.new(workflowId)
    var parsedList = Json.parse(jsonString)
    if (parsedList is List) {
      for (map in parsedList) {
        var event = HistoryEvent.fromMap(map)
        log.addRestoredEvent(event)
      }
    }
    return log
  }
}
