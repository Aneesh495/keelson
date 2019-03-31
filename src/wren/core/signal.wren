// Asynchronous signal mailbox and channel communication for Keelson workflows.
// Enables external events (human approvals, webhooks, cancellations) to unblock workflows.

import "./errors" for KeelsonError

class SignalChannel {
  construct new(maxCapacity) {
    _maxCapacity = (maxCapacity != null) ? maxCapacity : 1000
    _mailboxes = {}
    _waitingFibers = {}
  }

  // Sends a signal with an associated payload into the workflow's mailbox.
  send(signalName, payload) {
    if (!_mailboxes.containsKey(signalName)) {
      _mailboxes[signalName] = []
    }

    if (_mailboxes[signalName].count >= _maxCapacity) {
      Fiber.abort("Signal mailbox full for channel: " + signalName)
    }

    _mailboxes[signalName].add(payload)

    // If a fiber was waiting on this signal, wake it up
    if (_waitingFibers.containsKey(signalName) && _waitingFibers[signalName].count > 0) {
      var waitingFiber = _waitingFibers[signalName].removeAt(0)
      return waitingFiber
    }

    return null
  }

  // Checks whether a signal is currently buffered in the mailbox.
  hasPending(signalName) {
    if (!_mailboxes.containsKey(signalName)) return false
    return _mailboxes[signalName].count > 0
  }

  // Consumes the next pending signal payload from the mailbox.
  consume(signalName) {
    if (!hasPending(signalName)) return null
    return _mailboxes[signalName].removeAt(0)
  }

  // Registers a fiber to wait for the next incoming signal on signalName.
  registerWaitingFiber(signalName, fiber) {
    if (!_waitingFibers.containsKey(signalName)) {
      _waitingFibers[signalName] = []
    }
    _waitingFibers[signalName].add(fiber)
  }

  // Returns count of pending signals for a channel.
  pendingCount(signalName) {
    if (!_mailboxes.containsKey(signalName)) return 0
    return _mailboxes[signalName].count
  }

  clear() {
    _mailboxes.clear()
    _waitingFibers.clear()
  }
}
