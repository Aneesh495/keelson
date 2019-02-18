// Keelson lightweight test harness for Wren.
// Provides structured test suites, assertions, failure diagnostics, and summary reports.

class TestFailure {
  construct new(testName, expected, actual, message) {
    _testName = testName
    _expected = expected
    _actual = actual
    _message = message
  }

  testName { _testName }
  expected { _expected }
  actual { _actual }
  message { _message }

  toString {
    var desc = ""
    if (_message != null) {
      desc = " - " + _message
    }
    return "[FAIL] " + _testName + desc + "\n       Expected: " + _expected.toString + "\n       Actual:   " + _actual.toString
  }
}

class TestRunner {
  static init() {
    __suites = []
    __currentSuite = null
    __passCount = 0
    __failCount = 0
    __failures = []
  }

  static describe(suiteName, fn) {
    if (__suites == null) init()
    __currentSuite = suiteName
    System.print("\n=== Suite: " + suiteName + " ===")
    fn.call()
    __currentSuite = null
  }

  static test(testName, fn) {
    var fullName = testName
    if (__currentSuite != null) {
      fullName = __currentSuite + " > " + testName
    }
    var fiber = Fiber.new(fn)
    var error = fiber.try()

    if (error == null) {
      __passCount = __passCount + 1
      System.print("  [OK] " + testName)
    } else {
      __failCount = __failCount + 1
      var failure = TestFailure.new(fullName, "Success", error.toString, "Uncaught error during test execution")
      __failures.add(failure)
      System.print("  [FAIL] " + testName)
      System.print("         Error: " + error.toString)
    }
  }

  static assertEqual(expected, actual) {
    assertEqual(expected, actual, null)
  }

  static assertEqual(expected, actual, message) {
    if (expected != actual) {
      var msg = "Values are not equal"
      if (message != null) msg = message
      Fiber.abort("Assertion failed: " + msg + ". Expected '" + expected.toString + "', got '" + actual.toString + "'")
    }
  }

  static assertTrue(condition) {
    assertTrue(condition, null)
  }

  static assertTrue(condition, message) {
    if (!condition) {
      var msg = "Expected condition to be true"
      if (message != null) msg = message
      Fiber.abort("Assertion failed: " + msg)
    }
  }

  static assertFalse(condition) {
    assertFalse(condition, null)
  }

  static assertFalse(condition, message) {
    if (condition) {
      var msg = "Expected condition to be false"
      if (message != null) msg = message
      Fiber.abort("Assertion failed: " + msg)
    }
  }

  static assertNull(value) {
    assertNull(value, null)
  }

  static assertNull(value, message) {
    if (value != null) {
      var msg = "Expected value to be null"
      if (message != null) msg = message
      Fiber.abort("Assertion failed: " + msg + ", got '" + value.toString + "'")
    }
  }

  static assertNotNull(value) {
    assertNotNull(value, null)
  }

  static assertNotNull(value, message) {
    if (value == null) {
      var msg = "Expected value to be non-null"
      if (message != null) msg = message
      Fiber.abort("Assertion failed: " + msg)
    }
  }

  static assertThrows(fn, message) {
    var fiber = Fiber.new(fn)
    var error = fiber.try()
    if (error == null) {
      var msg = "Expected closure to throw an exception"
      if (message != null) msg = message
      Fiber.abort("Assertion failed: " + msg)
    }
  }

  static report() {
    System.print("\n------------------------------------------------------------")
    System.print("Test Results: " + __passCount.toString + " passed, " + __failCount.toString + " failed.")

    if (__failures.count > 0) {
      System.print("\nFailures:")
      for (f in __failures) {
        System.print(f.toString)
      }
      System.print("------------------------------------------------------------\n")
      return false
    }

    System.print("All tests completed successfully.")
    System.print("------------------------------------------------------------\n")
    return true
  }

  static passCount { __passCount }
  static failCount { __failCount }
}
