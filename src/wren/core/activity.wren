// Activity task definitions, metadata, and execution state.
// Activities encapsulate asynchronous, side-effecting external operations.

import "./retry_policy" for RetryPolicy
import "./errors" for ActivityError, TimeoutError

class ActivityStatus {
  static PENDING { "PENDING" }
  static RUNNING { "RUNNING" }
  static COMPLETED { "COMPLETED" }
  static FAILED { "FAILED" }
  static TIMED_OUT { "TIMED_OUT" }
  static CANCELLED { "CANCELLED" }
}

class ActivityDefinition {
  construct new(name, handler) {
    _name = name
    _handler = handler
    _defaultRetryPolicy = RetryPolicy.new()
    _defaultTimeoutMs = 60000
  }

  name { _name }
  handler { _handler }
  defaultRetryPolicy { _defaultRetryPolicy }
  defaultTimeoutMs { _defaultTimeoutMs }

  retryPolicy(policy) {
    _defaultRetryPolicy = policy
    return this
  }

  timeout(ms) {
    _defaultTimeoutMs = ms
    return this
  }
}

class ActivityTask {
  construct new(id, activityType, input, retryPolicy, timeoutMs) {
    _id = id
    _activityType = activityType
    _input = input
    _retryPolicy = (retryPolicy != null) ? retryPolicy : RetryPolicy.new()
    _timeoutMs = (timeoutMs != null) ? timeoutMs : 60000
    _status = ActivityStatus.PENDING
    _attempt = 1
    _result = null
    _error = null
    _scheduledAt = 0
    _startedAt = 0
    _completedAt = 0
  }

  id { _id }
  activityType { _activityType }
  input { _input }
  retryPolicy { _retryPolicy }
  timeoutMs { _timeoutMs }
  status { _status }
  attempt { _attempt }
  result { _result }
  error { _error }
  scheduledAt { _scheduledAt }
  startedAt { _startedAt }
  completedAt { _completedAt }

  isTerminal {
    return _status == ActivityStatus.COMPLETED ||
           _status == ActivityStatus.FAILED ||
           _status == ActivityStatus.TIMED_OUT ||
           _status == ActivityStatus.CANCELLED
  }

  markStarted(timestamp) {
    _status = ActivityStatus.RUNNING
    _startedAt = timestamp
  }

  markCompleted(res, timestamp) {
    _status = ActivityStatus.COMPLETED
    _result = res
    _completedAt = timestamp
  }

  markFailed(err, timestamp) {
    _status = ActivityStatus.FAILED
    _error = err
    _completedAt = timestamp
  }

  markTimedOut(timestamp) {
    _status = ActivityStatus.TIMED_OUT
    _error = TimeoutError.new(_activityType, _timeoutMs)
    _completedAt = timestamp
  }

  incrementAttempt() {
    _attempt = _attempt + 1
    _status = ActivityStatus.PENDING
  }

  toString { "ActivityTask(" + _id + ":" + _activityType + ", status: " + _status + ", attempt: " + _attempt.toString + ")" }
}

class ActivityRegistry {
  construct new() {
    _definitions = {}
  }

  register(definition) {
    _definitions[definition.name] = definition
    return this
  }

  registerHandler(name, handler) {
    var def = ActivityDefinition.new(name, handler)
    _definitions[name] = def
    return def
  }

  has(name) { _definitions.containsKey(name) }

  get(name) {
    if (_definitions.containsKey(name)) {
      return _definitions[name]
    }
    return null
  }

  // Executes an activity directly with error boundary and retry policy logic.
  execute(task, clockTimestamp) {
    if (!_definitions.containsKey(task.activityType)) {
      task.markFailed(ActivityError.new(task.activityType, "Unregistered activity: " + task.activityType), clockTimestamp)
      return task
    }

    var def = _definitions[task.activityType]
    task.markStarted(clockTimestamp)

    var fiber = Fiber.new(Fn.new {
      return def.handler.call(task.input)
    })

    var res = fiber.try()

    if (fiber.error != null) {
      task.markFailed(fiber.error, clockTimestamp)
    } else {
      task.markCompleted(res, clockTimestamp)
    }

    return task
  }
}
