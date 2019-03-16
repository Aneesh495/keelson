// Tests for Hierarchical Nested Sagas in Keelson.

import "../test_framework" for TestRunner
import "../../src/wren/core/saga" for Saga, SagaStatus

TestRunner.describe("Hierarchical Nested Saga Orchestration", Fn.new {
  TestRunner.test("nested sub-saga executes and compensates within parent saga", Fn.new {
    var parentSaga = Saga.new("parent-ecommerce-order")
    var auditTrail = []

    // Parent Step 1: Charge customer
    parentSaga.addStep("charge_customer", Fn.new { |ctx|
      auditTrail.add("parent:charge_customer")
      return {"charge_id": "CH_100"}
    }, Fn.new { |res, ctx|
      auditTrail.add("parent:refund_customer")
    })

    // Parent Step 2: Warehouse fulfillment (Sub-Saga)
    parentSaga.addStep("warehouse_fulfillment", Fn.new { |ctx|
      auditTrail.add("parent:warehouse_start")

      var subSaga = Saga.new("warehouse-sub-saga")

      subSaga.addStep("pack_primary_item", Fn.new { |subCtx|
        auditTrail.add("sub:pack_primary")
        return {"box_id": "BOX-A"}
      }, Fn.new { |res, subCtx|
        auditTrail.add("sub:unpack_primary")
      })

      subSaga.addStep("pack_secondary_item", Fn.new { |subCtx|
        auditTrail.add("sub:pack_secondary_failed")
        Fiber.abort("Secondary item damaged in transit")
      }, Fn.new { |res, subCtx|
        auditTrail.add("sub:unpack_secondary")
      })

      var subSuccess = subSaga.execute()
      if (!subSuccess) {
        Fiber.abort("Warehouse sub-saga failed to pack items")
      }

      return "packed"
    }, Fn.new { |res, ctx|
      auditTrail.add("parent:warehouse_cleanup")
    })

    var success = parentSaga.execute()

    TestRunner.assertFalse(success, "Parent saga should fail due to sub-saga failure")
    TestRunner.assertEqual(SagaStatus.COMPENSATED, parentSaga.status)

    // Verify ordering of execution and nested compensation
    TestRunner.assertEqual(6, auditTrail.count)
    TestRunner.assertEqual("parent:charge_customer", auditTrail[0])
    TestRunner.assertEqual("parent:warehouse_start", auditTrail[1])
    TestRunner.assertEqual("sub:pack_primary", auditTrail[2])
    TestRunner.assertEqual("sub:pack_secondary_failed", auditTrail[3])
    TestRunner.assertEqual("sub:unpack_primary", auditTrail[4])
    TestRunner.assertEqual("parent:refund_customer", auditTrail[5])
  })
})
