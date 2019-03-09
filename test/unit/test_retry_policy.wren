// Unit tests for Keelson RetryPolicy and jitter calculation.

import "../test_framework" for TestRunner
import "../../src/wren/core/retry_policy" for RetryPolicy, JitterStrategy

TestRunner.describe("RetryPolicy Backoff and Jitter Calculation", Fn.new {
  TestRunner.test("exponential backoff increases delay deterministically with NONE jitter", Fn.new {
    var policy = RetryPolicy.new()
      .initialInterval(100)
      .backoffCoefficient(2.0)
      .maxInterval(5000)
      .maxAttempts(5)
      .jitter(JitterStrategy.NONE)

    TestRunner.assertEqual(100, policy.computeDelay(1))
    TestRunner.assertEqual(200, policy.computeDelay(2))
    TestRunner.assertEqual(400, policy.computeDelay(3))
    TestRunner.assertEqual(800, policy.computeDelay(4))
  })

  TestRunner.test("delay respects max interval cap", Fn.new {
    var policy = RetryPolicy.new()
      .initialInterval(1000)
      .backoffCoefficient(2.0)
      .maxInterval(3000)
      .jitter(JitterStrategy.NONE)

    TestRunner.assertEqual(1000, policy.computeDelay(1))
    TestRunner.assertEqual(2000, policy.computeDelay(2))
    TestRunner.assertEqual(3000, policy.computeDelay(3))
    TestRunner.assertEqual(3000, policy.computeDelay(4)) // Clamped at 3000
  })

  TestRunner.test("shouldRetry checks max attempts", Fn.new {
    var policy = RetryPolicy.new().maxAttempts(3)

    TestRunner.assertTrue(policy.shouldRetry(1, null))
    TestRunner.assertTrue(policy.shouldRetry(2, null))
    TestRunner.assertFalse(policy.shouldRetry(3, null))
    TestRunner.assertFalse(policy.shouldRetry(4, null))
  })

  TestRunner.test("shouldRetry identifies non-retryable errors", Fn.new {
    var policy = RetryPolicy.new()
      .maxAttempts(5)
      .addNonRetryableError("InvalidArgument")
      .addNonRetryableError("Unauthorized")

    TestRunner.assertTrue(policy.shouldRetry(1, "ConnectionTimeout"))
    TestRunner.assertFalse(policy.shouldRetry(1, "InvalidArgument: bad payload"))
    TestRunner.assertFalse(policy.shouldRetry(1, "Error 401 Unauthorized"))
  })

  TestRunner.test("jitter strategies produce bounded delays", Fn.new {
    var policyFull = RetryPolicy.new()
      .initialInterval(200)
      .backoffCoefficient(2.0)
      .jitter(JitterStrategy.FULL)

    var delay1 = policyFull.computeDelay(2)
    TestRunner.assertTrue(delay1 >= 0 && delay1 <= 400)

    var policyEqual = RetryPolicy.new()
      .initialInterval(200)
      .backoffCoefficient(2.0)
      .jitter(JitterStrategy.EQUAL)

    var delay2 = policyEqual.computeDelay(2)
    TestRunner.assertTrue(delay2 >= 200 && delay2 <= 400)
  })
})
