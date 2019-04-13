// Tri-state Circuit Breaker for protecting activities and external services.
// States: CLOSED (healthy), OPEN (failing fast), HALF_OPEN (probing recovery).

class CircuitBreakerState {
  static CLOSED { "CLOSED" }
  static OPEN { "OPEN" }
  static HALF_OPEN { "HALF_OPEN" }
}

class CircuitBreaker {
  construct new(failureThreshold, recoveryTimeoutMs) {
    _failureThreshold = (failureThreshold != null) ? failureThreshold : 5
    _recoveryTimeoutMs = (recoveryTimeoutMs != null) ? recoveryTimeoutMs : 10000
    _state = CircuitBreakerState.CLOSED
    _failureCount = 0
    _successCount = 0
    _lastStateChangeMs = 0
  }

  state { _state }
  failureCount { _failureCount }
  successCount { _successCount }

  // Determines whether a call is allowed through the circuit breaker.
  allowRequest(currentTimeMs) {
    if (_state == CircuitBreakerState.CLOSED) {
      return true
    }

    if (_state == CircuitBreakerState.OPEN) {
      // Check if recovery timeout has elapsed to allow probe request
      if (currentTimeMs - _lastStateChangeMs >= _recoveryTimeoutMs) {
        _state = CircuitBreakerState.HALF_OPEN
        _lastStateChangeMs = currentTimeMs
        return true
      }
      return false
    }

    if (_state == CircuitBreakerState.HALF_OPEN) {
      // Allow single probe request
      return true
    }

    return false
  }

  // Records a successful call execution.
  recordSuccess(currentTimeMs) {
    if (_state == CircuitBreakerState.HALF_OPEN) {
      // Recovery confirmed
      _state = CircuitBreakerState.CLOSED
      _failureCount = 0
      _successCount = _successCount + 1
      _lastStateChangeMs = currentTimeMs
    } else if (_state == CircuitBreakerState.CLOSED) {
      _failureCount = 0
      _successCount = _successCount + 1
    }
  }

  // Records a failed call execution.
  recordFailure(currentTimeMs) {
    _failureCount = _failureCount + 1

    if (_state == CircuitBreakerState.HALF_OPEN) {
      // Probe failed, trip immediately back to OPEN
      _state = CircuitBreakerState.OPEN
      _lastStateChangeMs = currentTimeMs
    } else if (_state == CircuitBreakerState.CLOSED) {
      if (_failureCount >= _failureThreshold) {
        _state = CircuitBreakerState.OPEN
        _lastStateChangeMs = currentTimeMs
      }
    }
  }

  reset() {
    _state = CircuitBreakerState.CLOSED
    _failureCount = 0
    _successCount = 0
    _lastStateChangeMs = 0
  }
}
