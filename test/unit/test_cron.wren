// Unit tests for Keelson CronExpression parser.

import "../test_framework" for TestRunner
import "../../src/wren/core/cron" for CronExpression

TestRunner.describe("CronExpression Parsing and Schedule Matching", Fn.new {
  TestRunner.test("wildcard matches any timestamp", Fn.new {
    var cron = CronExpression.new("* * * * *")
    TestRunner.assertTrue(cron.matches(0, 0, 1, 1, 0))
    TestRunner.assertTrue(cron.matches(45, 14, 22, 11, 4))
  })

  TestRunner.test("specific hour and minute matching", Fn.new {
    var cron = CronExpression.new("30 2 * * *")
    TestRunner.assertTrue(cron.matches(30, 2, 15, 6, 1))
    TestRunner.assertFalse(cron.matches(31, 2, 15, 6, 1))
    TestRunner.assertFalse(cron.matches(30, 3, 15, 6, 1))
  })

  TestRunner.test("step expressions match intervals", Fn.new {
    var cron = CronExpression.new("*/15 * * * *")
    TestRunner.assertTrue(cron.matches(0, 10, 1, 1, 1))
    TestRunner.assertTrue(cron.matches(15, 10, 1, 1, 1))
    TestRunner.assertTrue(cron.matches(30, 10, 1, 1, 1))
    TestRunner.assertTrue(cron.matches(45, 10, 1, 1, 1))
    TestRunner.assertFalse(cron.matches(10, 10, 1, 1, 1))
  })

  TestRunner.test("range expressions match bounds", Fn.new {
    // 9 AM Monday through Friday (1 to 5)
    var cron = CronExpression.new("0 9 * * 1-5")
    TestRunner.assertTrue(cron.matches(0, 9, 10, 5, 1)) // Monday
    TestRunner.assertTrue(cron.matches(0, 9, 14, 5, 5)) // Friday
    TestRunner.assertFalse(cron.matches(0, 9, 15, 5, 6)) // Saturday
    TestRunner.assertFalse(cron.matches(0, 9, 16, 5, 0)) // Sunday
  })

  TestRunner.test("comma list expressions match distinct values", Fn.new {
    var cron = CronExpression.new("0 0 1,15 * *")
    TestRunner.assertTrue(cron.matches(0, 0, 1, 1, 2))
    TestRunner.assertTrue(cron.matches(0, 0, 15, 1, 2))
    TestRunner.assertFalse(cron.matches(0, 0, 10, 1, 2))
  })
})
