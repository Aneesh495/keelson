// Comprehensive unit tests for Keelson JSON parser and serializer.

import "../test_framework" for TestRunner
import "../../src/wren/core/json" for Json

TestRunner.describe("JSON Parser and Serializer", Fn.new {
  TestRunner.test("parse primitives", Fn.new {
    TestRunner.assertEqual("hello world", Json.parse("\"hello world\""))
    TestRunner.assertEqual(42, Json.parse("42"))
    TestRunner.assertEqual(-17.5, Json.parse("-17.5"))
    TestRunner.assertTrue(Json.parse("true"))
    TestRunner.assertFalse(Json.parse("false"))
    TestRunner.assertNull(Json.parse("null"))
  })

  TestRunner.test("parse string escapes", Fn.new {
    var parsed = Json.parse("\"line 1\\nline 2\\ttab\\\"quoted\\\"\"")
    TestRunner.assertEqual("line 1\nline 2\ttab\"quoted\"", parsed)
  })

  TestRunner.test("parse arrays and nested lists", Fn.new {
    var list = Json.parse("[1, 2, \"three\", true, null]")
    TestRunner.assertEqual(5, list.count)
    TestRunner.assertEqual(1, list[0])
    TestRunner.assertEqual(2, list[1])
    TestRunner.assertEqual("three", list[2])
    TestRunner.assertEqual(true, list[3])
    TestRunner.assertEqual(null, list[4])

    var nested = Json.parse("[[1, 2], [3, 4]]")
    TestRunner.assertEqual(2, nested.count)
    TestRunner.assertEqual(1, nested[0][0])
    TestRunner.assertEqual(4, nested[1][1])
  })

  TestRunner.test("parse objects and nested maps", Fn.new {
    var raw = "{\"id\": \"wf-101\", \"status\": \"RUNNING\", \"attempts\": 3, \"active\": true}"
    var obj = Json.parse(raw)
    TestRunner.assertEqual("wf-101", obj["id"])
    TestRunner.assertEqual("RUNNING", obj["status"])
    TestRunner.assertEqual(3, obj["attempts"])
    TestRunner.assertEqual(true, obj["active"])
  })

  TestRunner.test("stringify primitives and objects", Fn.new {
    TestRunner.assertEqual("\"test\"", Json.stringify("test"))
    TestRunner.assertEqual("123", Json.stringify(123))
    TestRunner.assertEqual("true", Json.stringify(true))
    TestRunner.assertEqual("false", Json.stringify(false))
    TestRunner.assertEqual("null", Json.stringify(null))

    var list = [1, "two", false]
    TestRunner.assertEqual("[1,\"two\",false]", Json.stringify(list))

    var map = {"key": "value"}
    TestRunner.assertEqual("{\"key\":\"value\"}", Json.stringify(map))
  })

  TestRunner.test("round-trip complex workflow event payload", Fn.new {
    var original = {
      "workflowId": "order-saga-981",
      "eventType": "ActivityTaskScheduled",
      "timestamp": 1700000000,
      "payload": {
        "amount": 250.75,
        "currency": "USD",
        "items": ["sku-1", "sku-2"],
        "reconciled": false
      }
    }

    var jsonStr = Json.stringify(original)
    var decoded = Json.parse(jsonStr)

    TestRunner.assertEqual("order-saga-981", decoded["workflowId"])
    TestRunner.assertEqual("ActivityTaskScheduled", decoded["eventType"])
    TestRunner.assertEqual(250.75, decoded["payload"]["amount"])
    TestRunner.assertEqual(2, decoded["payload"]["items"].count)
    TestRunner.assertEqual("sku-2", decoded["payload"]["items"][1])
    TestRunner.assertEqual(false, decoded["payload"]["reconciled"])
  })

  TestRunner.test("pretty formatting outputs indentation", Fn.new {
    var data = {"name": "saga", "steps": [1, 2]}
    var formatted = Json.pretty(data, 2)
    TestRunner.assertTrue(formatted.contains("\n"))
    TestRunner.assertTrue(formatted.contains("  "))
  })

  TestRunner.test("syntax error throws abort", Fn.new {
    TestRunner.assertThrows(Fn.new {
      Json.parse("{\"broken\": ")
    }, "Incomplete object should throw error")

    TestRunner.assertThrows(Fn.new {
      Json.parse("[1, 2,")
    }, "Incomplete array should throw error")
  })
})
