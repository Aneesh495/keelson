// Unit tests for Keelson MetricsRegistry, Counters, Gauges, and Histograms.

import "../test_framework" for TestRunner
import "../../src/wren/core/metrics" for MetricsRegistry

TestRunner.describe("MetricsRegistry and Prometheus Export", Fn.new {
  TestRunner.test("counters and gauges track values accurately", Fn.new {
    var reg = MetricsRegistry.new()
    var wfStarted = reg.counter("keelson_workflows_started_total", "help")
    wfStarted.inc()
    wfStarted.incBy(4)
    TestRunner.assertEqual(5, wfStarted.value)

    var activeG = reg.gauge("keelson_active_workflows", "help")
    activeG.set(10)
    activeG.inc()
    activeG.dec()
    TestRunner.assertEqual(10, activeG.value)
  })

  TestRunner.test("histograms track counts, sums, and percentiles", Fn.new {
    var reg = MetricsRegistry.new()
    var hist = reg.histogram("test_latency", "test", [10, 50, 100])

    hist.observe(10)
    hist.observe(20)
    hist.observe(30)
    hist.observe(40)
    hist.observe(50)
    hist.observe(100)

    TestRunner.assertEqual(6, hist.count)
    TestRunner.assertEqual(250, hist.sum)

    var p50 = hist.percentile(0.5)
    TestRunner.assertTrue(p50 >= 20 && p50 <= 40)

    var p99 = hist.percentile(0.99)
    TestRunner.assertEqual(100, p99)
  })

  TestRunner.test("toPrometheus formats valid exposition text", Fn.new {
    var reg = MetricsRegistry.new()
    reg.counter("app_events_total", "total events").inc()

    var promText = reg.toPrometheus()
    TestRunner.assertTrue(promText.contains("# HELP app_events_total total events"))
    TestRunner.assertTrue(promText.contains("# TYPE app_events_total counter"))
    TestRunner.assertTrue(promText.contains("app_events_total 1"))
  })
})
