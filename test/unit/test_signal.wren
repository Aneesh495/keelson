// Unit tests for Keelson SignalChannel and asynchronous message passing.

import "../test_framework" for TestRunner
import "../../src/wren/core/signal" for SignalChannel

TestRunner.describe("SignalChannel Mailbox Communication", Fn.new {
  TestRunner.test("FIFO message buffering and consumption", Fn.new {
    var channel = SignalChannel.new(10)
    TestRunner.assertFalse(channel.hasPending("approval"))

    channel.send("approval", {"decision": "APPROVED", "by": "alice"})
    channel.send("approval", {"decision": "REJECTED", "by": "bob"})

    TestRunner.assertTrue(channel.hasPending("approval"))
    TestRunner.assertEqual(2, channel.pendingCount("approval"))

    var sig1 = channel.consume("approval")
    TestRunner.assertEqual("APPROVED", sig1["decision"])
    TestRunner.assertEqual("alice", sig1["by"])

    var sig2 = channel.consume("approval")
    TestRunner.assertEqual("REJECTED", sig2["decision"])
    TestRunner.assertEqual("bob", sig2["by"])

    TestRunner.assertFalse(channel.hasPending("approval"))
    TestRunner.assertNull(channel.consume("approval"))
  })

  TestRunner.test("mailbox capacity limits prevent memory exhaustion", Fn.new {
    var boundedChannel = SignalChannel.new(2)
    boundedChannel.send("telemetry", {"val": 1})
    boundedChannel.send("telemetry", {"val": 2})

    TestRunner.assertThrows(Fn.new {
      boundedChannel.send("telemetry", {"val": 3})
    }, "Sending past capacity should throw error")
  })
})
