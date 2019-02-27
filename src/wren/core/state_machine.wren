// Deterministic finite state machine for workflows, tasks, and sagas.
// Enforces allowed state transitions and executes lifecycle hooks.

import "./errors" for StateTransitionError

class StateTransitionRecord {
  construct new(fromState, toState, timestamp, context) {
    _fromState = fromState
    _toState = toState
    _timestamp = timestamp
    _context = context
  }

  fromState { _fromState }
  toState { _toState }
  timestamp { _timestamp }
  context { _context }

  toString { "Transition(" + _fromState + " -> " + _toState + " at " + _timestamp.toString + ")" }
}

class StateMachine {
  construct new(entityName, initialState) {
    _entityName = entityName
    _currentState = initialState
    _transitions = {}
    _enterHooks = {}
    _exitHooks = {}
    _history = []
  }

  entityName { _entityName }
  currentState { _currentState }
  history { _history }

  // Defines an allowed directed transition from fromState to toState.
  allow(fromState, toState) {
    if (!_transitions.containsKey(fromState)) {
      _transitions[fromState] = []
    }
    if (!_transitions[fromState].contains(toState)) {
      _transitions[fromState].add(toState)
    }
    return this
  }

  // Registers a callback to execute when entering a state.
  onEnter(state, hook) {
    if (!_enterHooks.containsKey(state)) {
      _enterHooks[state] = []
    }
    _enterHooks[state].add(hook)
    return this
  }

  // Registers a callback to execute when exiting a state.
  onExit(state, hook) {
    if (!_exitHooks.containsKey(state)) {
      _exitHooks[state] = []
    }
    _exitHooks[state].add(hook)
    return this
  }

  // Checks whether transition to targetState is permitted.
  canTransitionTo(targetState) {
    if (!_transitions.containsKey(_currentState)) {
      return false
    }
    return _transitions[_currentState].contains(targetState)
  }

  // Executes a state transition. Throws StateTransitionError if forbidden.
  transition(targetState) {
    return transitionWithContext(targetState, null)
  }

  transitionWithContext(targetState, context) {
    if (!canTransitionTo(targetState)) {
      Fiber.abort(StateTransitionError.new(_entityName, _currentState, targetState).toString)
    }

    var oldState = _currentState

    // Execute exit hooks for previous state
    if (_exitHooks.containsKey(oldState)) {
      for (hook in _exitHooks[oldState]) {
        hook.call(oldState, targetState, context)
      }
    }

    _currentState = targetState

    // Record transition history
    var record = StateTransitionRecord.new(oldState, targetState, _history.count + 1, context)
    _history.add(record)

    // Execute enter hooks for new state
    if (_enterHooks.containsKey(targetState)) {
      for (hook in _enterHooks[targetState]) {
        hook.call(oldState, targetState, context)
      }
    }

    return record
  }

  // Resets state machine directly to a target state for replay/rehydration.
  rehydrate(targetState) {
    _currentState = targetState
  }
}
