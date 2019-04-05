// Synchronous read-only query dispatch for inspecting live workflow state.
// Guarantees non-mutating execution invariants without modifying event history.

class QueryRegistry {
  construct new() {
    _handlers = {}
  }

  // Registers a query handler function for a specific query name.
  register(queryName, handler) {
    _handlers[queryName] = handler
    return this
  }

  has(queryName) {
    return _handlers.containsKey(queryName)
  }

  // Executes a registered query against a workflow instance.
  dispatch(workflow, queryName, args) {
    if (!_handlers.containsKey(queryName)) {
      Fiber.abort("Unregistered query type: " + queryName)
    }

    var handler = _handlers[queryName]
    var fiber = Fiber.new(Fn.new {
      return handler.call(workflow, args)
    })

    var res = fiber.try()

    if (fiber.error != null) {
      Fiber.abort("Query execution failed: " + fiber.error.toString)
    }

    return res
  }
}
