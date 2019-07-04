// Cooperative fiber pool and priority task scheduler for Keelson workflows.
// Manages fiber lifecycles, cooperative yields, context switching, and error isolation.

import "./priority_queue" for PriorityQueue
import "./errors" for WorkflowError

class FiberTask {
  construct new(id, fiber, priority, context) {
    _id = id
    _fiber = fiber
    _priority = priority
    _context = context
    _state = "READY"
    _result = null
    _error = null
    _createdAt = 0
    _yieldCount = 0
    _yieldValue = null
  }

  id { _id }
  fiber { _fiber }
  priority { _priority }
  context { _context }
  state { _state }
  result { _result }
  error { _error }
  yieldCount { _yieldCount }
  yieldValue { _yieldValue }

  isDone { _state == "COMPLETED" || _state == "FAILED" || _state == "CANCELLED" }

  markRunning() {
    _state = "RUNNING"
  }

  markSuspended(val) {
    _state = "SUSPENDED"
    _yieldValue = val
    _yieldCount = _yieldCount + 1
  }

  markCompleted(res) {
    _state = "COMPLETED"
    _result = res
  }

  markFailed(err) {
    _state = "FAILED"
    _error = err
  }

  markCancelled() {
    _state = "CANCELLED"
  }

  toString { "FiberTask(" + _id + ", state: " + _state + ", priority: " + _priority.toString + ")" }
}

class FiberPool {
  construct new() {
    _queue = PriorityQueue.new()
    _tasks = {}
    _activeTask = null
    _contextSwitches = 0
    _completedCount = 0
    _failedCount = 0
  }

  queueCount { _queue.count }
  activeTask { _activeTask }
  contextSwitches { _contextSwitches }
  completedCount { _completedCount }
  failedCount { _failedCount }

  // Spawns a new task in the fiber pool with an execution closure and priority.
  spawn(id, fn) {
    return spawnWithPriority(id, 100, null, fn)
  }

  spawnWithPriority(id, priority, context, fn) {
    var fiber = Fiber.new(fn)
    var task = FiberTask.new(id, fiber, priority, context)
    _tasks[id] = task
    _queue.push(task, priority)
    return task
  }

  // Enqueues an existing suspended task back into the run queue.
  resume(taskId, priority) {
    if (!_tasks.containsKey(taskId)) {
      Fiber.abort("Cannot resume unknown task: " + taskId)
    }
    var task = _tasks[taskId]
    if (task.isDone) return
    task.markRunning()
    _queue.push(task, priority)
  }

  getTask(id) {
    if (_tasks.containsKey(id)) {
      return _tasks[id]
    }
    return null
  }

  // Executes one scheduled fiber step.
  // Returns true if work was executed, false if the queue was empty.
  step() {
    if (_queue.isEmpty) {
      return false
    }

    var task = _queue.pop()
    if (task.isDone) {
      return true
    }

    _activeTask = task
    _contextSwitches = _contextSwitches + 1
    task.markRunning()

    // Resume the fiber and isolate any runtime faults
    var res = task.fiber.try()

    if (task.fiber.error != null) {
      task.markFailed(task.fiber.error)
      _failedCount = _failedCount + 1
      _activeTask = null
      return true
    }

    if (task.fiber.isDone) {
      task.markCompleted(res)
      _completedCount = _completedCount + 1
      _activeTask = null
      return true
    }

    // Fiber yielded cooperatively
    task.markSuspended(res)
    _activeTask = null
    return true
  }

  // Runs all scheduled fibers until the priority queue is exhausted or maxSteps is reached.
  runUntilQuiescent(maxSteps) {
    var steps = 0
    while (!_queue.isEmpty && steps < maxSteps) {
      step()
      steps = steps + 1
    }
    return steps
  }

  // Cooperatively yields execution from the currently active fiber.
  static yield() {
    return Fiber.yield()
  }

  // Cooperatively yields with a value payload.
  static yieldValue(val) {
    return Fiber.yield(val)
  }
}
