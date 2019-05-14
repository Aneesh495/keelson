// Integration tests for Cloud Provisioning Saga and automated stack rollback.

import "../test_framework" for TestRunner
import "../../src/wren/workflows/cloud_provisioning_saga" for CloudProvisioningWorkflow
import "../../src/wren/core/saga" for SagaStatus

TestRunner.describe("Cloud Infrastructure Provisioning Saga", Fn.new {
  TestRunner.test("provisions complete cloud stack when health checks pass", Fn.new {
    var wf = CloudProvisioningWorkflow.new("cloud-prod-1")
    var spec = {
      "clusterName": "k8s-prod-us-east",
      "region": "us-east-1",
      "cidr": "10.100.0.0/16",
      "instanceCount": 3,
      "simulateHealthCheckFailure": false
    }

    var result = wf.execute(spec)

    TestRunner.assertEqual("ACTIVE", result["status"])
    TestRunner.assertEqual("k8s-prod-us-east", result["clusterName"])
    TestRunner.assertEqual("vpc-0a81f3d4", result["vpcId"])
    TestRunner.assertEqual(3, result["nodes"])
    TestRunner.assertTrue(result["dnsName"].contains("prod-alb"))
  })

  TestRunner.test("unhealthy cluster probe triggers full infrastructure rollback", Fn.new {
    var wf = CloudProvisioningWorkflow.new("cloud-faulty-1")
    var spec = {
      "clusterName": "k8s-canary-broken",
      "region": "us-west-2",
      "cidr": "10.200.0.0/16",
      "instanceCount": 2,
      "simulateHealthCheckFailure": true // Force probe failure
    }

    var result = wf.execute(spec)

    TestRunner.assertEqual("PROVISIONING_FAILED_AND_ROLLED_BACK", result["status"])

    // Verify reverse teardown order:
    // Step 5: Terminate Instances
    // Step 4: Delete Load Balancer
    // Step 3: Delete Security Group
    // Step 2: Delete Subnets
    // Step 1: Delete VPC
    var audit = result["tearDownAudit"]
    TestRunner.assertEqual(5, audit.count)
    TestRunner.assertEqual("terminate_instances:nodegroup-t3-large", audit[0])
    TestRunner.assertEqual("delete_load_balancer:arn:aws:elasticloadbalancing:us-east-1:123456:app/prod-alb", audit[1])
    TestRunner.assertEqual("delete_security_group:sg-cluster-web", audit[2])
    TestRunner.assertEqual("delete_subnets:subnet-pub-01,subnet-priv-01", audit[3])
    TestRunner.assertEqual("delete_vpc:vpc-0a81f3d4", audit[4])

    TestRunner.assertEqual(SagaStatus.COMPENSATED, wf.saga.status)
  })
})
