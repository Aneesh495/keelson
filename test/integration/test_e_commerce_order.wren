// Integration tests for production e-commerce checkout saga.

import "../test_framework" for TestRunner
import "../../src/wren/workflows/e_commerce_order_saga" for OrderSagaWorkflow
import "../../src/wren/core/saga" for SagaStatus

TestRunner.describe("E-Commerce Order Saga Workflows", Fn.new {
  TestRunner.test("clean low-risk order completes all 5 steps successfully", Fn.new {
    var wf = OrderSagaWorkflow.new("order-success-100")
    var order = {
      "orderId": "ORD-100",
      "customerId": "CUST-42",
      "customerEmail": "customer@example.com",
      "sku": "GPU-RTX-5090",
      "quantity": 1,
      "amount": 1999.00,
      "riskScore": 12 // Low risk
    }

    var result = wf.execute(order)

    TestRunner.assertEqual("CONFIRMED", result["status"])
    TestRunner.assertEqual("ORD-100", result["orderId"])
    TestRunner.assertEqual("TRK-7719283011", result["trackingNumber"])
    TestRunner.assertEqual("TXN-90210", result["transactionId"])

    var audit = result["auditLog"]
    TestRunner.assertEqual(5, audit.count)
    TestRunner.assertEqual("inventory_locked", audit[0])
    TestRunner.assertEqual("payment_authorized:1999", audit[1])
    TestRunner.assertEqual("fraud_passed", audit[2])
    TestRunner.assertEqual("carrier_dispatched", audit[3])
    TestRunner.assertEqual("receipt_emailed", audit[4])
  })

  TestRunner.test("high-risk fraud order triggers automatic reverse compensation", Fn.new {
    var wf = OrderSagaWorkflow.new("order-fraud-999")
    var highRiskOrder = {
      "orderId": "ORD-FRAUD-999",
      "customerId": "CUST-SUSPECT-7",
      "customerEmail": "burner@darkweb.org",
      "sku": "GOLD-BAR-1OZ",
      "quantity": 10,
      "amount": 25000.00,
      "riskScore": 95 // Trips fraud engine!
    }

    var result = wf.execute(highRiskOrder)

    TestRunner.assertEqual("REJECTED_AND_COMPENSATED", result["status"])
    TestRunner.assertEqual("ORD-FRAUD-999", result["orderId"])

    var audit = result["auditLog"]
    // Audit must contain:
    // 0: inventory_locked
    // 1: payment_authorized:25000
    // 2: fraud_rejected:score_95
    // 3: payment_refunded:TXN-90210 (reverse step 2)
    // 4: inventory_released:RES-TOK-8841 (reverse step 1)
    TestRunner.assertEqual(5, audit.count)
    TestRunner.assertEqual("inventory_locked", audit[0])
    TestRunner.assertEqual("payment_authorized:25000", audit[1])
    TestRunner.assertEqual("fraud_rejected:score_95", audit[2])
    TestRunner.assertEqual("payment_refunded:TXN-90210", audit[3])
    TestRunner.assertEqual("inventory_released:RES-TOK-8841", audit[4])

    TestRunner.assertEqual(SagaStatus.COMPENSATED, wf.saga.status)
  })
})
