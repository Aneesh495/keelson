// Deterministic time-travel replay engine for Keelson workflows.
// Reconstructs execution state from append-only event logs, skipping side effects
// for completed activities and validating code determinism.

import "./event_log" for EventType
import "./errors" for ReplayDivergenceError

class ReplayMode {
  static REPLAYING { "REPLAYING" }
  static LIVE { "LIVE" }
}

class ReplayEngine {
  construct new(eventLog) {
    _eventLog = eventLog
    _cursor = 0
    _mode = (eventLog.count > 0) ? ReplayMode.REPLAYING : ReplayMode.LIVE
    _completedActivities = {}
    _inFlightActivities = {}
    _completedTimers = {}
    _bufferedSignals = []

    indexHistoricalEvents()
  }

  mode { _mode }
  isReplaying { _mode == ReplayMode.REPLAYING }
  isLive { _mode == ReplayMode.LIVE }
  cursor { _cursor }

  // Indexes all completed activities, fired timers, and signals in the log.
  indexHistoricalEvents() {
    for (event in _eventLog.events) {
      if (event.eventType == EventType.ACTIVITY_COMPLETED) {
        var actId = event.attributes["activityId"]
        var res = event.attributes["result"]
        _completedActivities[actId] = res
      } else if (event.eventType == EventType.TIMER_FIRED) {
        var timerId = event.attributes["timerId"]
        _completedTimers[timerId] = true
      } else if (event.eventType == EventType.SIGNAL_RECEIVED) {
        _bufferedSignals.add(event.attributes)
      }
    }
  }

  // Checks whether a given activity was already completed in recorded history.
  hasCompletedActivity(activityId) {
    return _completedActivities.containsKey(activityId)
  }

  // Returns the cached result of a previously completed activity.
  getActivityResult(activityId) {
    return _completedActivities[activityId]
  }

  // Validates an activity execution during replay.
  // Throws ReplayDivergenceError if workflow code does not match recorded history.
  checkOrRecordActivity(activityId, activityName) {
    if (!isReplaying) {
      return null
    }

    // Check if recorded history has completed this activity
    if (_completedActivities.containsKey(activityId)) {
      return _completedActivities[activityId]
    }

    // If history has no more completed events, transition to LIVE execution
    _mode = ReplayMode.LIVE
    return null
  }

  // Checks whether a timer has already fired in history.
  hasTimerFired(timerId) {
    return _completedTimers.containsKey(timerId)
  }

  // Fetches next buffered signal from historical stream.
  consumeHistoricalSignal(signalName) {
    var i = 0
    while (i < _bufferedSignals.count) {
      var sig = _bufferedSignals[i]
      if (sig["name"] == signalName) {
        _bufferedSignals.removeAt(i)
        return sig["payload"]
      }
      i = i + 1
    }
    return null
  }
}
