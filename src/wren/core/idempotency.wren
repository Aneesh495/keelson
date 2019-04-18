// Idempotency manager for deduplicating workflow triggers and activity executions.
// Caches results by idempotency key with TTL expiration and payload collision checks.

class IdempotencyRecord {
  construct new(key, payloadHash, response, expiresAtMs) {
    _key = key
    _payloadHash = payloadHash
    _response = response
    _expiresAtMs = expiresAtMs
  }

  key { _key }
  payloadHash { _payloadHash }
  response { _response }
  expiresAtMs { _expiresAtMs }

  isExpired(nowMs) { nowMs >= _expiresAtMs }
}

class IdempotencyManager {
  construct new(defaultTtlMs) {
    _defaultTtlMs = (defaultTtlMs != null) ? defaultTtlMs : 86400000 // 24 hours
    _cache = {}
  }

  // Registers an execution result with an idempotency key and payload hash.
  register(key, payloadHash, response, nowMs) {
    var expiresAt = nowMs + _defaultTtlMs
    var record = IdempotencyRecord.new(key, payloadHash, response, expiresAt)
    _cache[key] = record
    return record
  }

  // Checks whether an idempotency key has been recorded.
  // Throws an error if the key exists but with a different payload hash (payload collision!).
  get(key, payloadHash, nowMs) {
    if (!_cache.containsKey(key)) {
      return null
    }

    var record = _cache[key]

    if (record.isExpired(nowMs)) {
      _cache.remove(key)
      return null
    }

    // Verify payload hash matches
    if (payloadHash != null && record.payloadHash != payloadHash) {
      Fiber.abort("Idempotency conflict: key '" + key + "' was previously used with a different request payload")
    }

    return record.response
  }

  // Purges all expired records from cache.
  purgeExpired(nowMs) {
    var expiredKeys = []
    for (entry in _cache) {
      if (entry.value.isExpired(nowMs)) {
        expiredKeys.add(entry.key)
      }
    }
    for (k in expiredKeys) {
      _cache.remove(k)
    }
    return expiredKeys.count
  }

  count { _cache.count }
  clear() { _cache.clear() }
}
