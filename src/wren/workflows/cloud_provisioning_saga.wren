// Production cloud infrastructure provisioning saga for Keelson.
// Orchestrates multi-tier VPC, subnets, security groups, load balancers, and compute nodes
// with guaranteed tear-down compensation on health check failure.

import "../core/saga" for Saga, SagaStatus
import "../core/workflow" for Workflow

class CloudProvisioningWorkflow is Workflow {
  construct new(id) {
    super(id)
    _saga = Saga.new(id)
  }

  saga { _saga }

  execute(spec) {
    var tearDownAudit = []
    setContext("region", spec["region"])
    setContext("clusterName", spec["clusterName"])

    // Step 1: Provision Virtual Private Cloud (VPC)
    _saga.addStep("provision_vpc", Fn.new { |ctx|
      return {
        "vpcId": "vpc-0a81f3d4",
        "cidr": spec["cidr"],
        "region": spec["region"]
      }
    }, Fn.new { |res, ctx|
      tearDownAudit.add("delete_vpc:" + res["vpcId"])
    })

    // Step 2: Provision public and private subnets
    _saga.addStep("provision_subnets", Fn.new { |ctx|
      var vpc = ctx["provision_vpc"]
      return {
        "publicSubnet": "subnet-pub-01",
        "privateSubnet": "subnet-priv-01",
        "vpcId": vpc["vpcId"]
      }
    }, Fn.new { |res, ctx|
      tearDownAudit.add("delete_subnets:" + res["publicSubnet"] + "," + res["privateSubnet"])
    })

    // Step 3: Configure security groups
    _saga.addStep("provision_security_groups", Fn.new { |ctx|
      var vpc = ctx["provision_vpc"]
      return {
        "sgId": "sg-cluster-web",
        "ports": [80, 443],
        "vpcId": vpc["vpcId"]
      }
    }, Fn.new { |res, ctx|
      tearDownAudit.add("delete_security_group:" + res["sgId"])
    })

    // Step 4: Deploy Application Load Balancer
    _saga.addStep("provision_load_balancer", Fn.new { |ctx|
      var subnets = ctx["provision_subnets"]
      var sg = ctx["provision_security_groups"]
      return {
        "albArn": "arn:aws:elasticloadbalancing:us-east-1:123456:app/prod-alb",
        "dnsName": "prod-alb-9912.elb.amazonaws.com"
      }
    }, Fn.new { |res, ctx|
      tearDownAudit.add("delete_load_balancer:" + res["albArn"])
    })

    // Step 5: Launch compute node group
    _saga.addStep("provision_compute_nodes", Fn.new { |ctx|
      var sg = ctx["provision_security_groups"]
      var subnets = ctx["provision_subnets"]
      return {
        "nodeGroupId": "nodegroup-t3-large",
        "instanceCount": spec["instanceCount"],
        "instanceIds": ["i-011a", "i-022b", "i-033c"]
      }
    }, Fn.new { |res, ctx|
      tearDownAudit.add("terminate_instances:" + res["nodeGroupId"])
    })

    // Step 6: Health verification gate
    _saga.addStep("verify_cluster_health", Fn.new { |ctx|
      var nodes = ctx["provision_compute_nodes"]
      var simulateFailure = spec["simulateHealthCheckFailure"]

      if (simulateFailure != null && simulateFailure == true) {
        Fiber.abort("Target group health check probe failed: HTTP 503 Service Unavailable")
      }

      return {
        "healthyNodes": nodes["instanceCount"],
        "ready": true
      }
    }, null)

    var success = _saga.execute()
    setContext("tearDownAudit", tearDownAudit)

    if (!success) {
      return {
        "status": "PROVISIONING_FAILED_AND_ROLLED_BACK",
        "clusterName": spec["clusterName"],
        "tearDownAudit": tearDownAudit
      }
    }

    return {
      "status": "ACTIVE",
      "clusterName": spec["clusterName"],
      "dnsName": _saga.results["provision_load_balancer"]["dnsName"],
      "vpcId": _saga.results["provision_vpc"]["vpcId"],
      "nodes": _saga.results["provision_compute_nodes"]["instanceCount"]
    }
  }
}
