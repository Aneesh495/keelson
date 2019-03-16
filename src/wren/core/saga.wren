// Distributed Saga Orchestration Engine for Keelson.
// Coordinates multi-step distributed workflows, tracks forward execution checkpoints,
// and guarantees reverse-topological backward compensation upon failures.

import "./errors" for SagaCompensationError, KeelsonError

class SagaStatus {
  static NOT_STARTED { "NOT_STARTED" }
  static RUNNING { "RUNNING" }
  static COMPLETED { "COMPLETED" }
  static COMPENSATING { "COMPENSATING" }
  static COMPENSATED { "COMPENSATED" }
  static FAILED { "FAILED" }
}

class SagaStep {
  construct new(name, forwardFn, compensationFn) {
    _name = name
    _forwardFn = forwardFn
    _compensationFn = compensationFn
    _executed = false
    _compensated = false
    _result = null
    _forwardError = null
    _compensationError = null
    _executionTimeMs = 0
  }

  name { _name }
  forwardFn { _forwardFn }
  compensationFn { _compensationFn }
  executed { _executed }
  compensated { _compensated }
  result { _result }
  forwardError { _forwardError }
  compensationError { _compensationError }
  executionTimeMs { _executionTimeMs }

  markExecuted(res, timeMs) {
    _executed = true
    _result = res
    _executionTimeMs = timeMs
  }

  markForwardFailed(err) {
    _forwardError = err
  }

  markCompensated() {
    _compensated = true
  }

  markCompensationFailed(err) {
    _compensationError = err
  }

  toString { "SagaStep(" + _name + ", executed: " + _executed.toString + ", compensated: " + _compensated.toString + ")" }
}

class SagaCompensationReport {
  construct new(sagaId, triggerError) {
    _sagaId = sagaId
    _triggerError = triggerError
    _compensatedSteps = []
    _failedCompensations = []
    _success = false
  }

  sagaId { _sagaId }
  triggerError { _triggerError }
  compensatedSteps { _compensatedSteps }
  failedCompensations { _failedCompensations }
  isSuccess { _success }

  markComplete() {
    _success = (_failedCompensations.count == 0)
  }

  addCompensated(stepName) {
    _compensatedSteps.add(stepName)
  }

  addFailed(stepName, err) {
    _failedCompensations.add({"step": stepName, "error": err.toString})
  }

  toString {
    return "SagaCompensationReport(saga: " + _sagaId + ", success: " + _success.toString + ", compensated: " + _compensatedSteps.count.toString + ", failed: " + _failedCompensations.count.toString + ")"
  }
}

class Saga {
  construct new(id) {
    _id = id
    _steps = []
    _status = SagaStatus.NOT_STARTED
    _results = {}
    _compensationReport = null
    _currentStepIndex = -1
    _onStepComplete = null
    _onCompensationStep = null
  }

  id { _id }
  status { _status }
  steps { _steps }
  results { _results }
  compensationReport { _compensationReport }

  onStepComplete(fn) {
    _onStepComplete = fn
    return this
  }

  onCompensationStep(fn) {
    _onCompensationStep = fn
    return this
  }

  // Adds a forward action and its reverse compensation to the saga pipeline.
  addStep(name, forwardFn, compensationFn) {
    var step = SagaStep.new(name, forwardFn, compensationFn)
    _steps.add(step)
    return this
  }

  // Executes the saga forward. If any step fails, automatically triggers backward compensation.
  execute() {
    _status = SagaStatus.RUNNING
    _currentStepIndex = 0

    for (i in 0..._steps.count) {
      _currentStepIndex = i
      var step = _steps[i]

      // Execute forward step in isolated fiber
      var fiber = Fiber.new(Fn.new {
        return step.forwardFn.call(_results)
      })

      var res = fiber.try()

      if (fiber.error != null) {
        step.markForwardFailed(fiber.error)
        _status = SagaStatus.FAILED

        // Initiate reverse compensation
        compensate(step.name, fiber.error)
        return false
      }

      step.markExecuted(res, 0)
      _results[step.name] = res

      if (_onStepComplete != null) {
        _onStepComplete.call(step.name, res)
      }
    }

    _status = SagaStatus.COMPLETED
    return true
  }

  // Executes backward compensation in reverse topological order.
  compensate(failedStepName, triggerError) {
    _status = SagaStatus.COMPENSATING
    _compensationReport = SagaCompensationReport.new(_id, triggerError)

    // Traverse previously completed steps in reverse order
    var i = _currentStepIndex - 1
    while (i >= 0) {
      var step = _steps[i]

      if (step.executed && step.compensationFn != null) {
        if (_onCompensationStep != null) {
          _onCompensationStep.call(step.name)
        }

        var compFiber = Fiber.new(Fn.new {
          step.compensationFn.call(step.result, _results)
        })

        compFiber.try()

        if (compFiber.error != null) {
          step.markCompensationFailed(compFiber.error)
          _compensationReport.addFailed(step.name, compFiber.error)
        } else {
          step.markCompensated()
          _compensationReport.addCompensated(step.name)
        }
      }

      i = i - 1
    }

    _compensationReport.markComplete()
    _status = (_compensationReport.isSuccess) ? SagaStatus.COMPENSATED : SagaStatus.FAILED
    return _compensationReport
  }
}
