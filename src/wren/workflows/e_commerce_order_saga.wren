// Production-grade e-commerce order checkout saga for Keelson.
// Orchestrates inventory reservation, payment authorization, fraud risk screening,
// carrier shipping label generation, and reverse-topological compensation.

import "../core/saga" for Saga, SagaStatus
import "../core/workflow" for Workflow

class OrderSagaWorkflow is Workflow {
  construct new(id) {
    super(id)
    _saga = Saga.new(id)
  }

  saga { _saga }

  execute(order) {
    var auditLog = []
    setContext("orderId", order["orderId"])
    setContext("customerId", order["customerId"])
    setContext("amount", order["amount"])

    // Step 1: Reserve inventory across warehouses
    _saga.addStep("reserve_inventory", Fn.new { |ctx|
      auditLog.add("inventory_locked")
      return {
        "warehouseId": "WH-NORTHEAST-1",
        "sku": order["sku"],
        "quantity": order["quantity"],
        "reservationToken": "RES-TOK-8841"
      }
    }, Fn.new { |res, ctx|
      auditLog.add("inventory_released:" + res["reservationToken"])
      // Real-world rollback: release locked inventory items
    })

    // Step 2: Authorize payment with payment gateway
    _saga.addStep("authorize_payment", Fn.new { |ctx|
      var inv = ctx["reserve_inventory"]
      auditLog.add("payment_authorized:" + order["amount"].toString)
      return {
        "transactionId": "TXN-90210",
        "amount": order["amount"],
        "currency": "USD",
        "authCode": "AUTH-APPROVED"
      }
    }, Fn.new { |res, ctx|
      auditLog.add("payment_refunded:" + res["transactionId"])
      // Real-world rollback: refund or void the authorized payment
    })

    // Step 3: Automated fraud risk scoring gate
    _saga.addStep("fraud_risk_screening", Fn.new { |ctx|
      var riskScore = order["riskScore"]
      if (riskScore != null && riskScore > 80) {
        auditLog.add("fraud_rejected:score_" + riskScore.toString)
        Fiber.abort("Order rejected by automated fraud risk engine: score " + riskScore.toString)
      }
      auditLog.add("fraud_passed")
      return {"riskScore": riskScore, "verified": true}
    }, null)

    // Step 4: Generate carrier shipping label
    _saga.addStep("generate_shipping_label", Fn.new { |ctx|
      var auth = ctx["authorize_payment"]
      auditLog.add("carrier_dispatched")
      return {
        "carrier": "FedEx",
        "service": "PriorityOvernight",
        "trackingNumber": "TRK-7719283011",
        "labelUrl": "https://shipping.internal/labels/TRK-7719283011.pdf"
      }
    }, Fn.new { |res, ctx|
      auditLog.add("carrier_cancelled:" + res["trackingNumber"])
      // Real-world rollback: void the shipping label with carrier
    })

    // Step 5: Customer confirmation notification
    _saga.addStep("send_customer_receipt", Fn.new { |ctx|
      var tracking = ctx["generate_shipping_label"]
      auditLog.add("receipt_emailed")
      return {
        "recipient": order["customerEmail"],
        "tracking": tracking["trackingNumber"],
        "status": "SENT"
      }
    }, null)

    // Execute the complete saga pipeline
    var success = _saga.execute()

    setContext("auditLog", auditLog)

    if (!success) {
      return {
        "status": "REJECTED_AND_COMPENSATED",
        "orderId": order["orderId"],
        "compensationReport": _saga.compensationReport.toString,
        "auditLog": auditLog
      }
    }

    return {
      "status": "CONFIRMED",
      "orderId": order["orderId"],
      "trackingNumber": _saga.results["generate_shipping_label"]["trackingNumber"],
      "transactionId": _saga.results["authorize_payment"]["transactionId"],
      "auditLog": auditLog
    }
  }
}
