// Runnable example: E-Commerce Order Fulfillment Saga in Keelson.
// Demonstrates forward execution, automated fraud detection, and reverse compensation.

import "../src/wren/workflows/e_commerce_order_saga" for OrderSagaWorkflow
import "../src/wren/core/json" for Json

System.print("============================================================")
System.print("    KEELSON: RESILIENT SAGA ORCHESTRATION DEMONSTRATION     ")
System.print("============================================================\n")

System.print(">>> SCENARIO 1: Legitimate customer order (Low Risk)")
System.print("------------------------------------------------------------")

var lowRiskWorkflow = OrderSagaWorkflow.new("order-checkout-001")
var goodOrder = {
  "orderId": "ORD-2026-9041",
  "customerId": "CUST-ALICE-12",
  "customerEmail": "alice@company.com",
  "sku": "DEV-WORKSTATION-X1",
  "quantity": 1,
  "amount": 3499.00,
  "riskScore": 14
}

var resultGood = lowRiskWorkflow.execute(goodOrder)
System.print("Outcome: " + resultGood["status"])
System.print("Tracking Number: " + resultGood["trackingNumber"].toString)
System.print("Payment Auth:    " + resultGood["transactionId"].toString)
System.print("Audit Trail:")
for (entry in resultGood["auditLog"]) {
  System.print("  [+] " + entry)
}

System.print("\n>>> SCENARIO 2: Fraudulent dark-web carding order (High Risk)")
System.print("------------------------------------------------------------")

var highRiskWorkflow = OrderSagaWorkflow.new("order-checkout-002")
var badOrder = {
  "orderId": "ORD-2026-9999",
  "customerId": "CUST-ANON-99",
  "customerEmail": "stolen-drop@darkmail.net",
  "sku": "ROLEX-SUBMARINER-DATE",
  "quantity": 5,
  "amount": 75000.00,
  "riskScore": 96 // Automated fraud check fails at Step 3!
}

var resultBad = highRiskWorkflow.execute(badOrder)
System.print("Outcome: " + resultBad["status"])
System.print("Audit Trail (Notice reverse-topological rollback):")
for (entry in resultBad["auditLog"]) {
  if (entry.startsWith("fraud_rejected")) {
    System.print("  [!] " + entry)
  } else if (entry.contains("released") || entry.contains("refunded")) {
    System.print("  [-] COMPENSATION: " + entry)
  } else {
    System.print("  [+] " + entry)
  }
}

System.print("\n============================================================")
System.print("Saga execution completed. State integrity 100 percent preserved.")
System.print("============================================================")
