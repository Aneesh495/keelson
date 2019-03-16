// Unit tests for Keelson Saga Orchestrator and reverse-topological compensation.

import "../test_framework" for TestRunner
import "../../src/wren/core/saga" for Saga, SagaStatus

TestRunner.describe("Saga Orchestration and Backward Recovery", Fn.new {
  TestRunner.test("successful forward execution accumulates results", Fn.new {
    var saga = Saga.new("order-checkout")
    var audit = []

    saga.addStep("reserve_credit", Fn.new { |ctx|
      audit.add("credit_reserved")
      return {"auth_code": "AUTH-101", "amount": 100}
    }, Fn.new { |res, ctx|
      audit.add("credit_refunded")
    })

    saga.addStep("lock_inventory", Fn.new { |ctx|
      audit.add("inventory_locked")
      return {"warehouse_id": "WH-EAST", "sku": "ITEM-9"}
    }, Fn.new { |res, ctx|
      audit.add("inventory_released")
    })

    var success = saga.execute()

    TestRunner.assertTrue(success, "Saga should execute successfully")
    TestRunner.assertEqual(SagaStatus.COMPLETED, saga.status)
    TestRunner.assertEqual(2, audit.count)
    TestRunner.assertEqual("credit_reserved", audit[0])
    TestRunner.assertEqual("inventory_locked", audit[1])
    TestRunner.assertEqual("AUTH-101", saga.results["reserve_credit"]["auth_code"])
  })

  TestRunner.test("step failure triggers reverse compensation in exact reverse order", Fn.new {
    var saga = Saga.new("travel-booking")
    var executionTrace = []
    var compensationTrace = []

    // Step 1: Book Hotel
    saga.addStep("book_hotel", Fn.new { |ctx|
      executionTrace.add("hotel_booked")
      return {"booking_id": "HT-456"}
    }, Fn.new { |res, ctx|
      compensationTrace.add("hotel_cancelled:" + res["booking_id"])
    })

    // Step 2: Book Flight
    saga.addStep("book_flight", Fn.new { |ctx|
      executionTrace.add("flight_booked")
      return {"flight_id": "FL-789"}
    }, Fn.new { |res, ctx|
      compensationTrace.add("flight_cancelled:" + res["flight_id"])
    })

    // Step 3: Book Rental Car (Fails!)
    saga.addStep("book_car", Fn.new { |ctx|
      executionTrace.add("car_failed")
      Fiber.abort("No rental cars available at destination")
    }, Fn.new { |res, ctx|
      compensationTrace.add("car_cancelled")
    })

    var success = saga.execute()

    TestRunner.assertFalse(success, "Saga should fail when step 3 fails")
    TestRunner.assertEqual(SagaStatus.COMPENSATED, saga.status)

    // Verify forward trace stopped at step 3
    TestRunner.assertEqual(3, executionTrace.count)
    TestRunner.assertEqual("hotel_booked", executionTrace[0])
    TestRunner.assertEqual("flight_booked", executionTrace[1])
    TestRunner.assertEqual("car_failed", executionTrace[2])

    // Verify compensation ran in reverse order: Flight (Step 2) first, then Hotel (Step 1)
    TestRunner.assertEqual(2, compensationTrace.count)
    TestRunner.assertEqual("flight_cancelled:FL-789", compensationTrace[0])
    TestRunner.assertEqual("hotel_cancelled:HT-456", compensationTrace[1])

    // Verify compensation report
    var report = saga.compensationReport
    TestRunner.assertNotNull(report)
    TestRunner.assertTrue(report.isSuccess)
    TestRunner.assertEqual(2, report.compensatedSteps.count)
    TestRunner.assertEqual("book_flight", report.compensatedSteps[0])
    TestRunner.assertEqual("book_hotel", report.compensatedSteps[1])
  })

  TestRunner.test("compensation error handling records failed compensations", Fn.new {
    var saga = Saga.new("payment-settlement")

    saga.addStep("debit_account", Fn.new { |ctx|
      return "debit_done"
    }, Fn.new { |res, ctx|
      Fiber.abort("Core banking service unreachable during refund")
    })

    saga.addStep("credit_merchant", Fn.new { |ctx|
      Fiber.abort("Merchant account suspended")
    }, null)

    var success = saga.execute()

    TestRunner.assertFalse(success)
    TestRunner.assertEqual(SagaStatus.FAILED, saga.status)

    var report = saga.compensationReport
    TestRunner.assertFalse(report.isSuccess)
    TestRunner.assertEqual(1, report.failedCompensations.count)
    TestRunner.assertEqual("debit_account", report.failedCompensations[0]["step"])
    TestRunner.assertTrue(report.failedCompensations[0]["error"].contains("banking service unreachable"))
  })
})
