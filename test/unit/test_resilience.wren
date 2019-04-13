// Unit tests for CircuitBreaker and RateLimiter resilience patterns.

import "../test_framework" for TestRunner
import "../../src/wren/core/circuit_breaker" for CircuitBreaker, CircuitBreakerState
import "../../src/wren/core/rate_limiter" for TokenBucket, LeakyBucket

TestRunner.describe("CircuitBreaker FSM Lifecycle", Fn.new {
  TestRunner.test("trips to OPEN when failures exceed threshold", Fn.new {
    var cb = CircuitBreaker.new(3, 5000)
    TestRunner.assertEqual(CircuitBreakerState.CLOSED, cb.state)

    // Failures 1 and 2
    cb.recordFailure(1000)
    cb.recordFailure(1100)
    TestRunner.assertEqual(CircuitBreakerState.CLOSED, cb.state)
    TestRunner.assertTrue(cb.allowRequest(1200))

    // Failure 3 (reaches threshold) -> Trips to OPEN
    cb.recordFailure(1200)
    TestRunner.assertEqual(CircuitBreakerState.OPEN, cb.state)
    TestRunner.assertFalse(cb.allowRequest(1300))
  })

  TestRunner.test("transitions to HALF_OPEN after cooldown and resets on success", Fn.new {
    var cb = CircuitBreaker.new(2, 5000)
    cb.recordFailure(1000)
    cb.recordFailure(1100) // OPEN at 1100

    TestRunner.assertFalse(cb.allowRequest(2000)) // Only 900ms elapsed, still OPEN

    // 6000ms elapsed (exceeds 5000ms cooldown) -> Transitions to HALF_OPEN
    TestRunner.assertTrue(cb.allowRequest(7100))
    TestRunner.assertEqual(CircuitBreakerState.HALF_OPEN, cb.state)

    // Successful probe confirms recovery -> CLOSED
    cb.recordSuccess(7200)
    TestRunner.assertEqual(CircuitBreakerState.CLOSED, cb.state)
    TestRunner.assertTrue(cb.allowRequest(7300))
  })
})

TestRunner.describe("RateLimiter Token and Leaky Bucket Algorithms", Fn.new {
  TestRunner.test("TokenBucket consumes bursts and refills over time", Fn.new {
    var tb = TokenBucket.new(5, 2) // 5 max tokens, refills 2 tokens/sec
    TestRunner.assertTrue(tb.tryConsume(3, 1000))
    TestRunner.assertEqual(2, tb.tokens)

    TestRunner.assertTrue(tb.tryConsume(2, 1000))
    TestRunner.assertEqual(0, tb.tokens)

    // Next consume should be rejected (empty)
    TestRunner.assertFalse(tb.tryConsume(1, 1000))

    // After 1000ms (1 second), 2 tokens refilled
    TestRunner.assertTrue(tb.tryConsume(2, 2000))
    TestRunner.assertFalse(tb.tryConsume(1, 2000))
  })

  TestRunner.test("LeakyBucket enforces continuous outflow", Fn.new {
    var lb = LeakyBucket.new(10, 5) // Capacity 10, leaks 5/sec
    TestRunner.assertTrue(lb.tryAdd(8, 1000))
    TestRunner.assertFalse(lb.tryAdd(5, 1000)) // 8 + 5 = 13 > 10

    // After 1 second, 5 leaked -> waterLevel is 3
    TestRunner.assertTrue(lb.tryAdd(5, 2000)) // 3 + 5 = 8 <= 10
  })
})
