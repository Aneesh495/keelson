// Directed Acyclic Graph (DAG) orchestrator and parallel join barriers.
// Provides topological sorting, cycle detection (Kahn's algorithm), and join synchronization:
// joinAll, joinAny, and joinQuorum.

import "./errors" for CircularDependencyError

class DagNode {
  construct new(id, actionFn) {
    _id = id
    _actionFn = actionFn
    _dependencies = []
    _dependents = []
    _status = "PENDING"
    _result = null
    _error = null
  }

  id { _id }
  actionFn { _actionFn }
  dependencies { _dependencies }
  dependents { _dependents }
  status { _status }
  result { _result }
  error { _error }

  isDone { _status == "COMPLETED" || _status == "FAILED" }

  addDependency(node) {
    if (!_dependencies.contains(node)) {
      _dependencies.add(node)
      node.addDependent(this)
    }
  }

  addDependent(node) {
    if (!_dependents.contains(node)) {
      _dependents.add(node)
    }
  }

  markCompleted(res) {
    _status = "COMPLETED"
    _result = res
  }

  markFailed(err) {
    _status = "FAILED"
    _error = err
  }

  toString { "DagNode(" + _id + ", status: " + _status + ", deps: " + _dependencies.count.toString + ")" }
}

class Dag {
  construct new() {
    _nodes = {}
  }

  nodes { _nodes }
  count { _nodes.count }

  // Adds a task node to the DAG with an execution closure.
  addNode(id, actionFn) {
    var node = DagNode.new(id, actionFn)
    _nodes[id] = node
    return node
  }

  // Declares that task 'dependentId' depends on 'dependencyId'.
  addDependency(dependentId, dependencyId) {
    if (!_nodes.containsKey(dependentId)) {
      Fiber.abort("Unknown dependent node: " + dependentId)
    }
    if (!_nodes.containsKey(dependencyId)) {
      Fiber.abort("Unknown dependency node: " + dependencyId)
    }

    _nodes[dependentId].addDependency(_nodes[dependencyId])
  }

  // Performs topological sort using Kahn's algorithm.
  // Throws CircularDependencyError if a cycle is detected.
  topologicalSort() {
    var inDegree = {}
    for (entry in _nodes) {
      inDegree[entry.key] = entry.value.dependencies.count
    }

    var ready = []
    for (entry in inDegree) {
      if (entry.value == 0) {
        ready.add(_nodes[entry.key])
      }
    }

    var sorted = []

    while (ready.count > 0) {
      var node = ready.removeAt(0)
      sorted.add(node)

      for (dep in node.dependents) {
        inDegree[dep.id] = inDegree[dep.id] - 1
        if (inDegree[dep.id] == 0) {
          ready.add(dep)
        }
      }
    }

    if (sorted.count != _nodes.count) {
      Fiber.abort(CircularDependencyError.new("Cycle detected in DAG").toString)
    }

    return sorted
  }

  // Executes the DAG nodes in topological order.
  execute() {
    var order = topologicalSort()
    var results = {}

    for (node in order) {
      // Gather dependency results
      var depResults = {}
      for (d in node.dependencies) {
        depResults[d.id] = d.result
      }

      var fiber = Fiber.new(Fn.new {
        return node.actionFn.call(depResults)
      })

      var res = fiber.try()

      if (fiber.error != null) {
        node.markFailed(fiber.error)
        Fiber.abort("DAG execution failed at node " + node.id + ": " + fiber.error.toString)
      } else {
        node.markCompleted(res)
        results[node.id] = res
      }
    }

    return results
  }

  // Barrier joinAll: executes a list of functions, waiting for ALL to complete.
  static joinAll(tasks) {
    var results = []
    for (task in tasks) {
      var fiber = Fiber.new(task)
      var res = fiber.try()
      if (fiber.error != null) {
        Fiber.abort("joinAll task failed: " + fiber.error.toString)
      }
      results.add(res)
    }
    return results
  }

  // Barrier joinAny: returns the result of the FIRST task that succeeds.
  static joinAny(tasks) {
    for (task in tasks) {
      var fiber = Fiber.new(task)
      var res = fiber.try()
      if (fiber.error == null) {
        return res
      }
    }
    Fiber.abort("joinAny: all tasks failed")
  }

  // Barrier joinQuorum: returns results as soon as requiredCount tasks succeed.
  static joinQuorum(tasks, requiredCount) {
    var successes = []
    for (task in tasks) {
      var fiber = Fiber.new(task)
      var res = fiber.try()
      if (fiber.error == null) {
        successes.add(res)
        if (successes.count >= requiredCount) {
          return successes
        }
      }
    }
    Fiber.abort("joinQuorum: unable to reach quorum of " + requiredCount.toString + ", only " + successes.count.toString + " succeeded")
  }
}
