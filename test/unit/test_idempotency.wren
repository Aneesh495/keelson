// Unit tests for Keelson IdempotencyManager.

import "../test_framework" for TestRunner
import "../../src/wren/core/idempotency" for IdempotencyManager

TestRunner.describe("Idempotency Key Deduplication", Fn.new {
  TestRunner.test("returns cached response for identical key and payload", Fn.new {
    var mgr = IdempotencyManager.new(5000)
    mgr.register("req-101", "hash_abc", {"status": "SUCCESS", "txId": 999}, 1000)

    var cached = mgr.get("req-101", "hash_abc", 2000)
    TestRunner.assertNotNull(cached)
    TestRunner.assertEqual("SUCCESS", cached["status"])
    TestRunner.assertEqual(999, cached["txId"])
  })

  TestRunner.test("detects payload hash conflict for duplicate key", Fn.new {
    var mgr = IdempotencyManager.new(5000)
    mgr.register("req-dup", "hash_orig", {"val": 1}, 1000)

    TestRunner.assertThrows(Fn.new {
      mgr.get("req-dup", "hash_different", 2000)
    }, "Different payload with same idempotency key must abort")
  })

  TestRunner.test("expired records are discarded and purged", Fn.new {
    var mgr = IdempotencyManager.new(1000) // 1 second TTL
    mgr.register("exp-1", "h1", "data", 1000) // expires at 2000

    TestRunner.assertNotNull(mgr.get("exp-1", "h1", 1500))

    // At t=2500, key has expired
    TestRunner.assertNull(mgr.get("exp-1", "h1", 2500))

    mgr.register("exp-2", "h2", "data2", 1000) // expires at 2000
    var purged = mgr.purgeExpired(3000)
    TestRunner.assertEqual(1, purged)
    TestRunner.assertEqual(0, mgr.count)
  })
})
