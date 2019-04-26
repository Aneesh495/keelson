// Telemetry, metrics aggregator, and Prometheus exposition exporter for Keelson.
// Tracks counters, gauges, and latency histograms (P50, P90, P99) across workflows.

class Counter {
  construct new(name, help) {
    _name = name
    _help = help
    _value = 0
  }

  name { _name }
  help { _help }
  value { _value }

  inc() { incBy(1) }
  incBy(amount) { _value = _value + amount }
  reset() { _value = 0 }
}

class Gauge {
  construct new(name, help) {
    _name = name
    _help = help
    _value = 0
  }

  name { _name }
  help { _help }
  value { _value }

  set(val) { _value = val }
  inc() { _value = _value + 1 }
  dec() { _value = _value - 1 }
}

class Histogram {
  construct new(name, help, buckets) {
    _name = name
    _help = help
    _buckets = (buckets != null) ? buckets : [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
    _counts = {}
    for (b in _buckets) {
      _counts[b] = 0
    }
    _totalCount = 0
    _totalSum = 0
    _observations = []
  }

  name { _name }
  help { _help }
  count { _totalCount }
  sum { _totalSum }

  observe(val) {
    _totalCount = _totalCount + 1
    _totalSum = _totalSum + val
    _observations.add(val)

    for (b in _buckets) {
      if (val <= b) {
        _counts[b] = _counts[b] + 1
      }
    }
  }

  // Calculates approximate percentile (e.g. 0.50, 0.90, 0.99)
  percentile(p) {
    if (_observations.count == 0) return 0
    // Simple sort for percentile calculation
    var sorted = _observations.toList
    sortList(sorted)
    var index = ((sorted.count - 1) * p).round
    return sorted[index]
  }

  sortList(list) {
    // Insertion sort for small-to-medium histogram observations
    var n = list.count
    for (i in 1...n) {
      var key = list[i]
      var j = i - 1
      while (j >= 0 && list[j] > key) {
        list[j + 1] = list[j]
        j = j - 1
      }
      list[j + 1] = key
    }
  }
}

class MetricsRegistry {
  construct new() {
    _counters = {}
    _gauges = {}
    _histograms = {}

    initDefaultMetrics()
  }

  initDefaultMetrics() {
    counter("keelson_workflows_started_total", "Total workflows initiated")
    counter("keelson_workflows_completed_total", "Total workflows completed successfully")
    counter("keelson_workflows_failed_total", "Total workflows failed")
    counter("keelson_sagas_compensated_total", "Total sagas that executed backward compensation")
    counter("keelson_activities_executed_total", "Total activity tasks executed")

    gauge("keelson_active_workflows", "Number of currently active workflows")
    gauge("keelson_active_fibers", "Number of active fibers in pool")
    gauge("keelson_active_timers", "Number of pending durable timers")

    histogram("keelson_workflow_duration_ms", "Workflow end-to-end execution latency", [10, 50, 100, 500, 1000, 5000])
  }

  counter(name, help) {
    if (!_counters.containsKey(name)) {
      _counters[name] = Counter.new(name, help)
    }
    return _counters[name]
  }

  gauge(name, help) {
    if (!_gauges.containsKey(name)) {
      _gauges[name] = Gauge.new(name, help)
    }
    return _gauges[name]
  }

  histogram(name, help, buckets) {
    if (!_histograms.containsKey(name)) {
      _histograms[name] = Histogram.new(name, help, buckets)
    }
    return _histograms[name]
  }

  // Generates Prometheus text exposition format.
  toPrometheus() {
    var out = []

    for (entry in _counters) {
      var c = entry.value
      out.add("# HELP " + c.name + " " + c.help)
      out.add("# TYPE " + c.name + " counter")
      out.add(c.name + " " + c.value.toString)
    }

    for (entry in _gauges) {
      var g = entry.value
      out.add("# HELP " + g.name + " " + g.help)
      out.add("# TYPE " + g.name + " gauge")
      out.add(g.name + " " + g.value.toString)
    }

    for (entry in _histograms) {
      var h = entry.value
      out.add("# HELP " + h.name + " " + h.help)
      out.add("# TYPE " + h.name + " histogram")
      out.add(h.name + "_count " + h.count.toString)
      out.add(h.name + "_sum " + h.sum.toString)
    }

    return out.join("\n") + "\n"
  }
}
