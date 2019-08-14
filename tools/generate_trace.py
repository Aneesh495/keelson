#!/usr/bin/env python3
"""
Keelson Distributed Trace Generator
Transforms Keelson immutable event logs into Jaeger/OpenTelemetry compatible
distributed traces for end-to-end visualization of workflow lifecycles and sagas.
"""

import argparse
import json
import os
import sys
from typing import Any, Dict, List


def generate_spans_from_events(events: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not events:
        return {"data": []}

    workflow_id = events[0].get("workflow_id", "unknown_wf")
    trace_id = format(abs(hash(workflow_id)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, "032x")

    spans = []
    root_span_id = format(1, "016x")

    t_start = events[0].get("timestamp_ns", 0) // 1000  # microseconds
    t_end = events[-1].get("timestamp_ns", t_start + 1000) // 1000

    # Root workflow span
    spans.append({
        "traceID": trace_id,
        "spanID": root_span_id,
        "operationName": f"workflow:{workflow_id}",
        "references": [],
        "startTime": t_start,
        "duration": max(1, t_end - t_start),
        "tags": [
            {"key": "keelson.workflow_id", "type": "string", "value": workflow_id},
            {"key": "keelson.engine_version", "type": "string", "value": "1.0.0"},
            {"key": "service.name", "type": "string", "value": "keelson-engine"},
        ],
        "logs": [],
    })

    span_counter = 2
    activity_spans: Dict[str, Dict[str, Any]] = {}

    for evt in events:
        event_type = evt.get("event_type", "")
        payload = evt.get("payload", {})
        ts_us = evt.get("timestamp_ns", 0) // 1000

        if event_type == "ACTIVITY_SCHEDULED":
            task_name = payload.get("task_name", f"task_{span_counter}")
            span_id = format(span_counter, "016x")
            span_counter += 1
            activity_spans[task_name] = {
                "traceID": trace_id,
                "spanID": span_id,
                "operationName": f"activity:{task_name}",
                "references": [{"refType": "CHILD_OF", "traceID": trace_id, "spanID": root_span_id}],
                "startTime": ts_us,
                "duration": 0,
                "tags": [
                    {"key": "keelson.task_name", "type": "string", "value": task_name},
                    {"key": "component", "type": "string", "value": "keelson-activity"},
                ],
                "logs": [],
            }

        elif event_type in ("ACTIVITY_COMPLETED", "ACTIVITY_FAILED"):
            task_name = payload.get("task_name", payload.get("step", ""))
            if task_name in activity_spans:
                s = activity_spans[task_name]
                s["duration"] = max(1, ts_us - s["startTime"])
                status_tag = "OK" if event_type == "ACTIVITY_COMPLETED" else "ERROR"
                s["tags"].append({"key": "status", "type": "string", "value": status_tag})
                if "error" in payload:
                    s["tags"].append({"key": "error", "type": "bool", "value": True})
                    s["logs"].append({
                        "timestamp": ts_us,
                        "fields": [{"key": "event", "value": "error"}, {"key": "message", "value": str(payload["error"])}],
                    })
                spans.append(s)
                del activity_spans[task_name]

        elif event_type == "SAGA_COMPENSATING":
            step_name = payload.get("step", f"comp_{span_counter}")
            comp_span_id = format(span_counter, "016x")
            span_counter += 1
            spans.append({
                "traceID": trace_id,
                "spanID": comp_span_id,
                "operationName": f"compensation:{step_name}",
                "references": [{"refType": "CHILD_OF", "traceID": trace_id, "spanID": root_span_id}],
                "startTime": ts_us,
                "duration": 500,
                "tags": [
                    {"key": "keelson.compensation_step", "type": "string", "value": step_name},
                    {"key": "saga.rollback", "type": "bool", "value": True},
                ],
                "logs": [],
            })

    # Flush any remaining uncompleted spans
    for s in activity_spans.values():
        if s["duration"] == 0:
            s["duration"] = max(1, t_end - s["startTime"])
        spans.append(s)

    return {
        "data": [
            {
                "traceID": trace_id,
                "spans": spans,
                "processes": {
                    "p1": {
                        "serviceName": "keelson-engine",
                        "tags": [{"key": "hostname", "type": "string", "value": "localhost"}],
                    }
                },
            }
        ]
    }


def main():
    parser = argparse.ArgumentParser(description="Convert Keelson event log to Jaeger JSON trace.")
    parser.add_argument("event_file", help="Path to JSON file containing array of events")
    parser.add_argument("-o", "--output", help="Output trace file path (default: stdout)")

    args = parser.parse_args()

    with open(args.event_file, "r") as f:
        events = json.load(f)

    if isinstance(events, dict) and "events" in events:
        events = events["events"]

    trace_doc = generate_spans_from_events(events)
    formatted = json.dumps(trace_doc, indent=2)

    if args.output:
        with open(args.output, "w") as f:
            f.write(formatted)
        print(f"Generated trace with {len(trace_doc['data'][0]['spans'])} spans at '{args.output}'")
    else:
        print(formatted)


if __name__ == "__main__":
    main()
