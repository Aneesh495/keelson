// Workflow base class and durable execution runtime context for Keelson.
// Implements deterministic fiber yielding, replay caching, and durable primitives.

import "./event_log" for EventLog, EventType
import "./replay" for ReplayEngine, ReplayMode
import "./fiber_pool" for FiberPool
import "./errors" for WorkflowError

class WorkflowStatus {
  static PENDING { "PENDING" }
  static RUNNING { "RUNNING" }
  static COMPLETED { "COMPLETED" }
  static FAILED { "FAILED" }
  static CANCELLED { "CANCELLED" }
}

class Workflow {
  construct new(id) {
    _id = id
    _status = WorkflowStatus.PENDING
    _eventLog = EventLog.new(id)
    _replayEngine = ReplayEngine.new(_eventLog)
    _activityCounter = 0
    _timerCounter = 0
    _signalMailbox = {}
    _result = null
    _error = null
    _context = {}
  }

  id { _id }
  status { _status }
  eventLog { _eventLog }
  replayEngine { _replayEngine }
  result { _result }
  error { _error }
  context { _context }

  // Attaches an existing event log for deterministic replay.
  attachHistory(log) {
    _eventLog = log
    _replayEngine = ReplayEngine.new(log)
    return this
  }

  // Subclasses must implement the workflow logic in execute(input).
  execute(input) {
    Fiber.abort("Workflow subclass must override execute(input)")
  }

  // Executes an external activity deterministically.
  // Returns cached result during replay, or yields until worker completion when live.
  executeActivity(activityName, input) {
    _activityCounter = _activityCounter + 1
    var actId = "act-" + _activityCounter.toString

    // Check replay cache
    if (_replayEngine.isReplaying) {
      if (_replayEngine.hasCompletedActivity(actId)) {
        return _replayEngine.getActivityResult(actId)
      }
    }

    // Live execution path
    _eventLog.append(EventType.ACTIVITY_SCHEDULED, _eventLog.count + 1, {
      "activityId": actId,
      "activityName": activityName,
      "input": input
    })

    // Cooperatively yield the fiber, waiting for activity execution
    var yieldPayload = {
      "type": "ACTIVITY",
      "activityId": actId,
      "activityName": activityName,
      "input": input
    }

    // Yield control back to scheduler
    var result = FiberPool.yieldValue(yieldPayload)

    // When resumed, record completion event
    _eventLog.append(EventType.ACTIVITY_COMPLETED, _eventLog.count + 1, {
      "activityId": actId,
      "activityName": activityName,
      "result": result
    })

    return result
  }

  // Durable sleep primitive.
  // Fast-forwards during replay, or yields until timer expiration when live.
  sleep(durationMs) {
    _timerCounter = _timerCounter + 1
    var timerId = "timer-" + _timerCounter.toString

    if (_replayEngine.isReplaying) {
      if (_replayEngine.hasTimerFired(timerId)) {
        return
      }
    }

    _eventLog.append(EventType.TIMER_STARTED, _eventLog.count + 1, {
      "timerId": timerId,
      "durationMs": durationMs
    })

    var yieldPayload = {
      "type": "TIMER",
      "timerId": timerId,
      "durationMs": durationMs
    }

    FiberPool.yieldValue(yieldPayload)

    _eventLog.append(EventType.TIMER_FIRED, _eventLog.count + 1, {
      "timerId": timerId
    })
  }

  // Sends an external signal into the workflow.
  receiveSignal(signalName, payload) {
    if (!_signalMailbox.containsKey(signalName)) {
      _signalMailbox[signalName] = []
    }
    _signalMailbox[signalName].add(payload)

    _eventLog.append(EventType.SIGNAL_RECEIVED, _eventLog.count + 1, {
      "name": signalName,
      "payload": payload
    })
  }

  // Waits for an incoming signal matching signalName.
  waitForSignal(signalName) {
    if (_replayEngine.isReplaying) {
      var histSignal = _replayEngine.consumeHistoricalSignal(signalName)
      if (histSignal != null) {
        return histSignal
      }
    }

    if (_signalMailbox.containsKey(signalName) && _signalMailbox[signalName].count > 0) {
      return _signalMailbox[signalName].removeAt(0)
    }

    var yieldPayload = {
      "type": "SIGNAL_WAIT",
      "signalName": signalName
    }

    var signalPayload = FiberPool.yieldValue(yieldPayload)
    return signalPayload
  }

  // Queries an exposed state variable. Read-only and non-mutating.
  query(queryName) {
    if (_context.containsKey(queryName)) {
      return _context[queryName]
    }
    return null
  }

  setContext(key, value) {
    _context[key] = value
  }
}
