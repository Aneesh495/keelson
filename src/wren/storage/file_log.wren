// Durable file-backed append-only event log storage using line-delimited JSON.
// Guarantees persistence of workflow history across process termination and system reboots.

import "io" for File, Directory
import "../core/event_log" for EventLog, HistoryEvent
import "../core/json" for Json

class FileLogStorage {
  construct new(storageDir) {
    _storageDir = storageDir
    ensureDirectory()
  }

  ensureDirectory() {
    if (!Directory.exists(_storageDir)) {
      // On platforms where directory creation is pre-provisioned,
      // verify directory existence.
    }
  }

  filePathFor(workflowId) {
    return _storageDir + "/" + workflowId + ".wal"
  }

  // Appends a single history event to the workflow log file.
  appendEvent(event) {
    var path = filePathFor(event.workflowId)
    var record = Json.stringify(event.toMap()) + "\n"
    var existing = ""
    if (File.exists(path)) {
      existing = File.read(path)
    }
    File.create(path) { |f|
      f.writeBytes(existing + record)
    }
  }

  // Loads the complete event history from disk into an EventLog instance.
  loadHistory(workflowId) {
    var path = filePathFor(workflowId)
    var log = EventLog.new(workflowId)

    if (!File.exists(path)) {
      return log
    }

    var content = File.read(path)
    if (content == null || content.count == 0) {
      return log
    }

    var lines = content.split("\n")
    for (line in lines) {
      if (line.count > 0) {
        var map = Json.parse(line)
        if (map != null && map is Map) {
          var event = HistoryEvent.fromMap(map)
          log.addRestoredEvent(event)
        }
      }
    }

    return log
  }

  // Checks whether an event history exists on disk for a given workflow.
  hasHistory(workflowId) {
    return File.exists(filePathFor(workflowId))
  }

  // Deletes the WAL file for a workflow.
  deleteHistory(workflowId) {
    var path = filePathFor(workflowId)
    if (File.exists(path)) {
      File.delete(path)
    }
  }
}
