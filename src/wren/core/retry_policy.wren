// Configurable retry policies with exponential backoff and jitter algorithms.
// Controls activity retry loops, avoiding stampeding herd effects on downstream services.

class JitterStrategy {
  static NONE { "NONE" }
  static FULL { "FULL" }
  static EQUAL { "EQUAL" }
  static DECORRELATED { "DECORRELATED" }
}

class RetryPolicy {
  construct new() {
    _initialIntervalMs = 100
    _backoffCoefficient = 2.0
    _maxIntervalMs = 30000
    _maxAttempts = 3
    _jitter = JitterStrategy.FULL
    _nonRetryableErrors = []
    _seed = 123456789
  }

  // Builder pattern setters
  initialInterval(ms) {
    _initialIntervalMs = ms
    return this
  }

  backoffCoefficient(coef) {
    _backoffCoefficient = coef
    return this
  }

  maxInterval(ms) {
    _maxIntervalMs = ms
    return this
  }

  maxAttempts(attempts) {
    _maxAttempts = attempts
    return this
  }

  jitter(strategy) {
    _jitter = strategy
    return this
  }

  addNonRetryableError(errorType) {
    _nonRetryableErrors.add(errorType)
    return this
  }

  initialIntervalMs { _initialIntervalMs }
  backoffCoefficient { _backoffCoefficient }
  maxIntervalMs { _maxIntervalMs }
  maxAttempts { _maxAttempts }
  jitterStrategy { _jitter }
  nonRetryableErrors { _nonRetryableErrors }

  // Determines if an operation should be retried given the attempt count and error.
  shouldRetry(attempt, error) {
    if (attempt >= _maxAttempts) {
      return false
    }

    if (error != null) {
      var errStr = error.toString
      for (nonRetryable in _nonRetryableErrors) {
        if (errStr.contains(nonRetryable)) {
          return false
        }
      }
    }

    return true
  }

  // Computes the delay in milliseconds before the next retry attempt.
  computeDelay(attempt) {
    var rawDelay = _initialIntervalMs * (_backoffCoefficient.pow(attempt - 1))
    if (rawDelay > _maxIntervalMs) {
      rawDelay = _maxIntervalMs
    }

    if (_jitter == JitterStrategy.NONE) {
      return rawDelay.floor
    }

    if (_jitter == JitterStrategy.FULL) {
      var rand = pseudoRandom()
      return (rand * rawDelay).floor
    }

    if (_jitter == JitterStrategy.EQUAL) {
      var half = rawDelay / 2
      var rand = pseudoRandom()
      return (half + rand * half).floor
    }

    // Default fallback to raw delay
    return rawDelay.floor
  }

  // Deterministic Linear Congruential Generator (LCG) for reproducible jitter.
  pseudoRandom() {
    _seed = (1103515245 * _seed + 12345) % 2147483648
    return _seed / 2147483648
  }
}
