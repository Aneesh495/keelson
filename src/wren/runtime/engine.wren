// Unified runtime orchestrator for Keelson.
// Integrates FiberPool, ActivityRegistry, TimerWheel, SignalChannel,
// IdempotencyManager, MetricsRegistry, and durable EventLog storage.

import "../core/fiber_pool" for FiberPool
import "../core/activity" for ActivityRegistry, ActivityTask, ActivityStatus
import "../core/timer" for TimerWheel
import "../core/signal" for SignalChannel
import "../core/query" for QueryRegistry
import "../core/idempotency" for IdempotencyManager
import "../core/metrics" for MetricsRegistry
import "../core/event_log" for EventLog, EventType
import "../core/workflow" for WorkflowStatus

class WorkflowInstanceRecord {
  construct new(id, workflow, fiberTask, input, startedAtMs) {
    _id = id
    _workflow = workflow
    _fiberTask = fiberTask
    _input = input
    _startedAtMs = startedAtMs
    _completedAtMs = 0
    _status = WorkflowStatus.RUNNING
    _result = null
    _error = null
  }

  id { _id }
  workflow { _workflow }
  fiberTask { _fiberTask }
  input { _input }
  startedAtMs { _startedAtMs }
  completedAtMs { _completedAtMs }
  status { _status }
  result { _result }
  error { _error }

  markCompleted(res, nowMs) {
    _status = WorkflowStatus.COMPLETED
    _result = res
    _completedAtMs = nowMs
  }

  markFailed(err, nowMs) {
    _status = WorkflowStatus.FAILED
    _error = err
    _completedAtMs = nowMs
  }
}

class KeelsonEngine {
  construct new(storage) {
    _storage = storage
    _fiberPool = FiberPool.new()
    _activityRegistry = ActivityRegistry.new()
    _timerWheel = TimerWheel.new()
    _signalChannel = SignalChannel.new(1000)
    _queryRegistry = QueryRegistry.new()
    _idempotency = IdempotencyManager.new(86400000)
    _metrics = MetricsRegistry.new()

    _activeWorkflows = {}
    _completedWorkflows = {}
    _clockMs = 1000
  }

  clockMs { _clockMs }
  fiberPool { _fiberPool }
  activityRegistry { _activityRegistry }
  timerWheel { _timerWheel }
  signalChannel { _signalChannel }
  queryRegistry { _queryRegistry }
  idempotency { _idempotency }
  metrics { _metrics }

  advanceClock(deltaMs) {
    _clockMs = _clockMs + deltaMs
    _timerWheel.advance(_clockMs)
  }

  setClock(ms) {
    _clockMs = ms
    _timerWheel.advance(_clockMs)
  }

  // Registers an activity handler with the engine.
  registerActivity(name, handler) {
    return _activityRegistry.registerHandler(name, handler)
  }

  // Registers a query handler with the engine.
  registerQuery(name, handler) {
    return _queryRegistry.register(name, handler)
  }

  // Starts a new workflow execution.
  startWorkflow(id, workflow, input) {
    if (_activeWorkflows.containsKey(id)) {
      Fiber.abort("Workflow with ID '" + id + "' is already running")
    }

    _metrics.counter("keelson_workflows_started_total", "total").inc()
    _metrics.gauge("keelson_active_workflows", "active").inc()

    // Record start event in workflow's event log
    workflow.eventLog.append(EventType.WORKFLOW_STARTED, _clockMs, input)

    // Persist start event if storage is configured
    if (_storage != null) {
      _storage.appendEvent(workflow.eventLog.events[0])
    }

    // Spawn execution fiber in pool
    var fiberTask = _fiberPool.spawnWithPriority(id, 50, workflow, Fn.new {
      return workflow.execute(input)
    })

    var record = WorkflowInstanceRecord.new(id, workflow, fiberTask, input, _clockMs)
    _activeWorkflows[id] = record
    return record
  }

  // Sends an external signal to a running workflow.
  sendSignal(workflowId, signalName, payload) {
    if (!_activeWorkflows.containsKey(workflowId)) {
      Fiber.abort("Cannot send signal: workflow '" + workflowId + "' is not running")
    }

    var record = _activeWorkflows[workflowId]
    record.workflow.receiveSignal(signalName, payload)

    // Re-schedule fiber to resume from signal wait
    _fiberPool.resume(workflowId, 10)
  }

  // Queries an active workflow.
  queryWorkflow(workflowId, queryName, args) {
    var wf = null
    if (_activeWorkflows.containsKey(workflowId)) {
      wf = _activeWorkflows[workflowId].workflow
    } else if (_completedWorkflows.containsKey(workflowId)) {
      wf = _completedWorkflows[workflowId].workflow
    } else {
      Fiber.abort("Cannot query: workflow '" + workflowId + "' not found")
    }

    return _queryRegistry.dispatch(wf, queryName, args)
  }

  // Executes one engine scheduling step: timers, fibers, and activity dispatches.
  step() {
    // 1. Advance timer wheel
    var expiredTimers = _timerWheel.advance(_clockMs)
    for (timer in expiredTimers) {
      if (_activeWorkflows.containsKey(timer.id)) {
        _fiberPool.resume(timer.id, 20)
      }
    }

    // 2. Step the fiber scheduler if fibers are pending
    if (_fiberPool.queueCount > 0) {
      _fiberPool.step()
    }

    // 3. Process active workflows (suspensions, completions)
    checkActiveWorkflowTasks()

    return true
  }

  checkActiveWorkflowTasks() {
    var completedIds = []

    for (entry in _activeWorkflows) {
      var id = entry.key
      var record = entry.value

      if (record.fiberTask.state == "SUSPENDED") {
        handleSuspendedWorkflow(record)
      }

      if (record.fiberTask.isDone) {
        if (record.fiberTask.error != null) {
          record.markFailed(record.fiberTask.error, _clockMs)
          record.workflow.eventLog.append(EventType.WORKFLOW_FAILED, _clockMs, {"error": record.fiberTask.error.toString})
          _metrics.counter("keelson_workflows_failed_total", "failed").inc()
        } else {
          record.markCompleted(record.fiberTask.result, _clockMs)
          record.workflow.eventLog.append(EventType.WORKFLOW_COMPLETED, _clockMs, {"result": record.fiberTask.result})
          _metrics.counter("keelson_workflows_completed_total", "completed").inc()
        }

        _metrics.gauge("keelson_active_workflows", "active").dec()
        completedIds.add(id)
      }
    }

    for (id in completedIds) {
      _completedWorkflows[id] = _activeWorkflows[id]
      _activeWorkflows.remove(id)
    }
  }

  handleSuspendedWorkflow(record) {
    while (record.fiberTask.state == "SUSPENDED") {
      var yieldVal = record.fiberTask.yieldValue
      if (yieldVal is Map) {
        var type = yieldVal["type"]

        if (type == "ACTIVITY") {
          var actName = yieldVal["activityName"]
          var actInput = yieldVal["input"]
          var actId = yieldVal["activityId"]

          var actTask = ActivityTask.new(actId, actName, actInput, null, 10000)
          _metrics.counter("keelson_activities_executed_total", "acts").inc()
          _activityRegistry.execute(actTask, _clockMs)

          var nextYield = null
          if (actTask.status == ActivityStatus.COMPLETED) {
            nextYield = record.fiberTask.fiber.try(actTask.result)
          } else {
            nextYield = record.fiberTask.fiber.try(null)
          }

          if (record.fiberTask.fiber.error != null) {
            record.fiberTask.markFailed(record.fiberTask.fiber.error)
            break
          } else if (record.fiberTask.fiber.isDone) {
            record.fiberTask.markCompleted(nextYield)
            break
          } else {
            record.fiberTask.markSuspended(nextYield)
          }
        } else if (type == "TIMER") {
          var timerId = yieldVal["timerId"]
          var duration = yieldVal["durationMs"]
          _timerWheel.schedule(record.id, duration, _clockMs, null)
          break
        } else {
          break
        }
      } else {
        break
      }
    }
  }

  // Runs engine steps until the specific workflow reaches a terminal state.
  runUntilComplete(workflowId, maxSteps) {
    var steps = 0
    while (steps < maxSteps) {
      if (_completedWorkflows.containsKey(workflowId)) {
        return _completedWorkflows[workflowId]
      }
      step()
      steps = steps + 1
    }
    return getWorkflow(workflowId)
  }

  getWorkflow(id) {
    if (_activeWorkflows.containsKey(id)) return _activeWorkflows[id]
    if (_completedWorkflows.containsKey(id)) return _completedWorkflows[id]
    return null
  }
}
