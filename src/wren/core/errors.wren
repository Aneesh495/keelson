// Keelson core error hierarchy.
// Defines structured exceptions for workflow execution, activity failures,
// saga compensation faults, and replay divergence.

class KeelsonError {
  construct new(message) {
    _message = message
    _stackTrace = null
  }

  construct withCause(message, cause) {
    _message = message
    _cause = cause
    _stackTrace = null
  }

  message { _message }
  cause { _cause }
  stackTrace { _stackTrace }
  stackTrace=(val) { _stackTrace = val }

  toString {
    if (_cause != null) {
      return "%(type): %(_message) (Caused by: %(_cause))"
    }
    return "%(type): %(_message)"
  }

  type { "KeelsonError" }
}

class WorkflowError is KeelsonError {
  construct new(workflowId, message) {
    super(message)
    _workflowId = workflowId
  }

  construct withCause(workflowId, message, cause) {
    super.withCause(message, cause)
    _workflowId = workflowId
  }

  workflowId { _workflowId }
  type { "WorkflowError" }
}

class ActivityError is KeelsonError {
  construct new(activityName, message) {
    super(message)
    _activityName = activityName
    _retryable = true
    _attempt = 1
  }

  construct withDetails(activityName, message, retryable, attempt, cause) {
    super.withCause(message, cause)
    _activityName = activityName
    _retryable = retryable
    _attempt = attempt
  }

  activityName { _activityName }
  isRetryable { _retryable }
  attempt { _attempt }
  type { "ActivityError" }
}

class NonRetryableError is ActivityError {
  construct new(activityName, message) {
    super.withDetails(activityName, message, false, 1, null)
  }

  construct withCause(activityName, message, cause) {
    super.withDetails(activityName, message, false, 1, cause)
  }

  type { "NonRetryableError" }
}

class SagaCompensationError is KeelsonError {
  construct new(sagaId, failedStepName, message, cause) {
    super.withCause(message, cause)
    _sagaId = sagaId
    _failedStepName = failedStepName
  }

  sagaId { _sagaId }
  failedStepName { _failedStepName }
  type { "SagaCompensationError" }
}

class TimeoutError is KeelsonError {
  construct new(target, timeoutMs) {
    super("Operation on '%(target)' timed out after %(timeoutMs)ms")
    _target = target
    _timeoutMs = timeoutMs
  }

  target { _target }
  timeoutMs { _timeoutMs }
  type { "TimeoutError" }
}

class ReplayDivergenceError is KeelsonError {
  construct new(expectedEvent, actualEvent, eventIndex) {
    super("Replay divergence at event index %(eventIndex). Expected: %(expectedEvent), Actual: %(actualEvent)")
    _expectedEvent = expectedEvent
    _actualEvent = actualEvent
    _eventIndex = eventIndex
  }

  expectedEvent { _expectedEvent }
  actualEvent { _actualEvent }
  eventIndex { _eventIndex }
  type { "ReplayDivergenceError" }
}

class StateTransitionError is KeelsonError {
  construct new(entity, fromState, toState) {
    super("Invalid state transition for %(entity): cannot transition from '%(fromState)' to '%(toState)'")
    _entity = entity
    _fromState = fromState
    _toState = toState
  }

  entity { _entity }
  fromState { _fromState }
  toState { _toState }
  type { "StateTransitionError" }
}

class CircularDependencyError is KeelsonError {
  construct new(cyclePath) {
    super("Circular dependency detected in execution graph: %(cyclePath)")
    _cyclePath = cyclePath
  }

  cyclePath { _cyclePath }
  type { "CircularDependencyError" }
}
