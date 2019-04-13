// Token Bucket and Leaky Bucket rate limiters for activity task queues.
// Enforces burst bounds and steady-state throughput limits.

class TokenBucket {
  construct new(capacity, refillRatePerSec) {
    _capacity = capacity
    _refillRate = refillRatePerSec
    _tokens = capacity
    _lastRefillMs = 0
  }

  capacity { _capacity }
  tokens { _tokens }

  // Tries to consume requested tokens. Returns true if granted, false if rejected.
  tryConsume(requestedTokens, nowMs) {
    refill(nowMs)

    if (_tokens >= requestedTokens) {
      _tokens = _tokens - requestedTokens
      return true
    }

    return false
  }

  refill(nowMs) {
    if (_lastRefillMs == 0) {
      _lastRefillMs = nowMs
      return
    }

    var elapsedSec = (nowMs - _lastRefillMs) / 1000
    if (elapsedSec > 0) {
      var addedTokens = elapsedSec * _refillRate
      _tokens = _tokens + addedTokens
      if (_tokens > _capacity) {
        _tokens = _capacity
      }
      _lastRefillMs = nowMs
    }
  }
}

class LeakyBucket {
  construct new(capacity, leakRatePerSec) {
    _capacity = capacity
    _leakRate = leakRatePerSec
    _waterLevel = 0
    _lastLeakMs = 0
  }

  capacity { _capacity }
  waterLevel { _waterLevel }

  // Tries to add an event to the bucket.
  tryAdd(amount, nowMs) {
    leak(nowMs)

    if (_waterLevel + amount <= _capacity) {
      _waterLevel = _waterLevel + amount
      return true
    }

    return false
  }

  leak(nowMs) {
    if (_lastLeakMs == 0) {
      _lastLeakMs = nowMs
      return
    }

    var elapsedSec = (nowMs - _lastLeakMs) / 1000
    if (elapsedSec > 0) {
      var leaked = elapsedSec * _leakRate
      _waterLevel = _waterLevel - leaked
      if (_waterLevel < 0) {
        _waterLevel = 0
      }
      _lastLeakMs = nowMs
    }
  }
}
