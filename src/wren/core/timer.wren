// Durable timer scheduler and timing wheel for Keelson workflows.
// Uses a binary min-heap to efficiently track and fire durable delays and timeouts.

import "./priority_queue" for PriorityQueue

class DurableTimer {
  construct new(id, delayMs, createdAtMs, callback) {
    _id = id
    _delayMs = delayMs
    _createdAtMs = createdAtMs
    _fireAtMs = createdAtMs + delayMs
    _callback = callback
    _cancelled = false
    _fired = false
  }

  id { _id }
  delayMs { _delayMs }
  createdAtMs { _createdAtMs }
  fireAtMs { _fireAtMs }
  callback { _callback }
  isCancelled { _cancelled }
  isFired { _fired }

  cancel() {
    _cancelled = true
  }

  markFired() {
    _fired = true
  }

  toString { "DurableTimer(" + _id + ", fireAt: " + _fireAtMs.toString + ", fired: " + _fired.toString + ")" }
}

class TimerWheel {
  construct new() {
    _queue = PriorityQueue.new()
    _timers = {}
    _currentTimeMs = 0
  }

  currentTimeMs { _currentTimeMs }
  activeCount { _timers.count }
  isEmpty { _timers.count == 0 }

  // Schedules a new durable timer.
  schedule(timerId, delayMs, nowMs, callback) {
    _currentTimeMs = nowMs
    var timer = DurableTimer.new(timerId, delayMs, nowMs, callback)
    _timers[timerId] = timer
    _queue.push(timer, timer.fireAtMs)
    return timer
  }

  // Cancels a pending timer by ID.
  cancel(timerId) {
    if (_timers.containsKey(timerId)) {
      var timer = _timers[timerId]
      timer.cancel()
      _timers.remove(timerId)
      return true
    }
    return false
  }

  // Returns the earliest firing timestamp among active timers.
  nextDeadline() {
    while (!_queue.isEmpty) {
      var timer = _queue.peek()
      if (timer.isCancelled || timer.isFired) {
        _queue.pop()
      } else {
        return timer.fireAtMs
      }
    }
    return null
  }

  // Advances monotonic time and triggers all expired timers.
  // Returns the list of timers that were fired during this step.
  advance(nowMs) {
    _currentTimeMs = nowMs
    var firedTimers = []

    while (!_queue.isEmpty) {
      var timer = _queue.peek()

      if (timer.isCancelled) {
        _queue.pop()
        continue
      }

      if (timer.fireAtMs <= nowMs) {
        _queue.pop()
        timer.markFired()
        _timers.remove(timer.id)

        if (timer.callback != null) {
          timer.callback.call(timer)
        }

        firedTimers.add(timer)
      } else {
        // Earliest timer is still in the future
        break
      }
    }

    return firedTimers
  }
}
