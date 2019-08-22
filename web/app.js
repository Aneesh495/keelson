/**
 * Keelson Execution Dashboard Frontend Engine
 * Provides live workflow telemetry, visual pipeline rendering,
 * and deterministic time-travel event replay.
 */

// Offline demo dataset showcasing both clean runs and reverse-topological sagas
const MOCK_WORKFLOWS = [
  {
    id: "wf-ord-883921",
    type: "e_commerce_order_saga",
    status: "COMPLETED",
    duration: "42.8 ms",
    eventsCount: 10,
    compensated: "None (Clean Run)",
    steps: [
      { name: "lock_inventory", status: "completed", duration: "8.2 ms", comp: "release_inventory" },
      { name: "authorize_payment", status: "completed", duration: "12.4 ms", comp: "refund_payment" },
      { name: "fraud_risk_analysis", status: "completed", duration: "5.1 ms", comp: null },
      { name: "carrier_dispatch", status: "completed", duration: "14.1 ms", comp: "cancel_shipment" },
      { name: "send_receipt", status: "completed", duration: "3.0 ms", comp: null }
    ],
    events: [
      { id: 1, type: "WORKFLOW_STARTED", ts: "2026-11-22 17:00:00.100", payload: { order_id: "ORD-9912", amount_cents: 3499 } },
      { id: 2, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:00:00.105", payload: { step: "lock_inventory", sku: "SKU-PRO-42" } },
      { id: 3, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:00:00.113", payload: { step: "lock_inventory", reservation_id: "RES-TOK-8841" } },
      { id: 4, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:00:00.115", payload: { step: "authorize_payment", amount: 3499 } },
      { id: 5, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:00:00.127", payload: { step: "authorize_payment", auth_code: "TXN-90210" } },
      { id: 6, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:00:00.130", payload: { step: "fraud_risk_analysis" } },
      { id: 7, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:00:00.135", payload: { step: "fraud_risk_analysis", score: 0.08, status: "passed" } },
      { id: 8, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:00:00.138", payload: { step: "carrier_dispatch" } },
      { id: 9, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:00:00.152", payload: { step: "carrier_dispatch", tracking: "TRK-7719283011" } },
      { id: 10, type: "WORKFLOW_COMPLETED", ts: "2026-11-22 17:00:00.155", payload: { status: "confirmed", tracking: "TRK-7719283011" } }
    ]
  },
  {
    id: "wf-ord-992014",
    type: "e_commerce_order_saga",
    status: "COMPENSATED",
    duration: "58.2 ms",
    eventsCount: 9,
    compensated: "2 steps rolled back",
    steps: [
      { name: "lock_inventory", status: "compensated", duration: "7.9 ms", comp: "release_inventory:done" },
      { name: "authorize_payment", status: "compensated", duration: "11.2 ms", comp: "refund_payment:done" },
      { name: "fraud_risk_analysis", status: "failed", duration: "4.8 ms", comp: null }
    ],
    events: [
      { id: 1, type: "WORKFLOW_STARTED", ts: "2026-11-22 17:02:10.010", payload: { order_id: "ORD-9913", amount_cents: 75000 } },
      { id: 2, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:02:10.015", payload: { step: "lock_inventory" } },
      { id: 3, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:02:10.023", payload: { step: "lock_inventory", reservation_id: "RES-TOK-9912" } },
      { id: 4, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:02:10.025", payload: { step: "authorize_payment", amount: 75000 } },
      { id: 5, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:02:10.036", payload: { step: "authorize_payment", auth_code: "TXN-90211" } },
      { id: 6, type: "ACTIVITY_FAILED", ts: "2026-11-22 17:02:10.041", payload: { step: "fraud_risk_analysis", error: "FraudRiskExceeded: score 0.96" } },
      { id: 7, type: "SAGA_COMPENSATING", ts: "2026-11-22 17:02:10.045", payload: { step: "refund_payment", target_txn: "TXN-90211" } },
      { id: 8, type: "SAGA_COMPENSATING", ts: "2026-11-22 17:02:10.052", payload: { step: "release_inventory", target_res: "RES-TOK-9912" } },
      { id: 9, type: "WORKFLOW_COMPENSATED", ts: "2026-11-22 17:02:10.058", payload: { status: "rejected_and_compensated" } }
    ]
  },
  {
    id: "wf-cloud-00192",
    type: "cloud_provisioning_saga",
    status: "COMPENSATED",
    duration: "112.5 ms",
    eventsCount: 8,
    compensated: "VPC & Subnets destroyed",
    steps: [
      { name: "allocate_vpc", status: "compensated", duration: "18.1 ms", comp: "delete_vpc:done" },
      { name: "provision_subnets", status: "compensated", duration: "14.2 ms", comp: "delete_subnets:done" },
      { name: "deploy_k8s_cluster", status: "failed", duration: "45.0 ms", comp: null }
    ],
    events: [
      { id: 1, type: "WORKFLOW_STARTED", ts: "2026-11-22 17:05:00.000", payload: { region: "us-east-1", cluster_name: "prod-eks-01" } },
      { id: 2, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:05:00.018", payload: { step: "allocate_vpc", vpc_id: "vpc-0aa812f" } },
      { id: 3, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:05:00.032", payload: { step: "provision_subnets", count: 3 } },
      { id: 4, type: "ACTIVITY_FAILED", ts: "2026-11-22 17:05:00.077", payload: { step: "deploy_k8s_cluster", error: "VCPUQuotaExceeded" } },
      { id: 5, type: "SAGA_COMPENSATING", ts: "2026-11-22 17:05:00.085", payload: { step: "delete_subnets" } },
      { id: 6, type: "SAGA_COMPENSATING", ts: "2026-11-22 17:05:00.098", payload: { step: "delete_vpc", vpc_id: "vpc-0aa812f" } },
      { id: 7, type: "WORKFLOW_COMPENSATED", ts: "2026-11-22 17:05:00.112", payload: { rolled_back: true } }
    ]
  },
  {
    id: "wf-iot-558291",
    type: "firmware_rollout_canary",
    status: "RUNNING",
    duration: "185.0 ms",
    eventsCount: 6,
    compensated: "None (In Progress)",
    steps: [
      { name: "verify_payload_signature", status: "completed", duration: "10.0 ms", comp: null },
      { name: "deploy_stage_1_canary_1_pct", status: "completed", duration: "85.0 ms", comp: "rollback_stage_1" },
      { name: "deploy_stage_2_canary_10_pct", status: "running", duration: "90.0 ms", comp: "rollback_stage_2" }
    ],
    events: [
      { id: 1, type: "WORKFLOW_STARTED", ts: "2026-11-22 17:10:00.000", payload: { firmware_version: "v2.4.1", fleet_size: 10000 } },
      { id: 2, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:10:00.010", payload: { step: "verify_signature", valid: true } },
      { id: 3, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:10:00.095", payload: { stage: 1, devices_updated: 100, error_rate: 0.0 } },
      { id: 4, type: "ACTIVITY_SCHEDULED", ts: "2026-11-22 17:10:00.100", payload: { stage: 2, target_count: 1000 } }
    ]
  },
  {
    id: "wf-etl-110293",
    type: "distributed_etl_pipeline",
    status: "COMPLETED",
    duration: "210.4 ms",
    eventsCount: 8,
    compensated: "None (Clean Run)",
    steps: [
      { name: "extract_shard_0", status: "completed", duration: "45.1 ms", comp: null },
      { name: "extract_shard_1", status: "completed", duration: "48.2 ms", comp: null },
      { name: "transform_join_barrier", status: "completed", duration: "62.0 ms", comp: null },
      { name: "load_warehouse", status: "completed", duration: "55.1 ms", comp: "purge_staging_tables" }
    ],
    events: [
      { id: 1, type: "WORKFLOW_STARTED", ts: "2026-11-22 17:15:00.000", payload: { batch_id: "BATCH-2026-11-22-01", row_count: 500000 } },
      { id: 2, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:15:00.045", payload: { step: "extract_shard_0", rows: 250000 } },
      { id: 3, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:15:00.048", payload: { step: "extract_shard_1", rows: 250000 } },
      { id: 4, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:15:00.155", payload: { step: "transform_join", validated: true } },
      { id: 5, type: "ACTIVITY_COMPLETED", ts: "2026-11-22 17:15:00.210", payload: { step: "load_warehouse", partition: "20261122" } },
      { id: 6, type: "WORKFLOW_COMPLETED", ts: "2026-11-22 17:15:00.212", payload: { rows_committed: 500000 } }
    ]
  }
];

let selectedWorkflow = MOCK_WORKFLOWS[0];
let activeFilter = "all";

document.addEventListener("DOMContentLoaded", () => {
  renderSidebar();
  renderWorkflowDetail();
  setupEventListeners();
  loadPrometheusMetrics();
});

function renderSidebar() {
  const listEl = document.getElementById("workflow-list");
  const countEl = document.getElementById("workflow-count");
  const searchVal = document.getElementById("workflow-search").value.toLowerCase();

  const filtered = MOCK_WORKFLOWS.filter(w => {
    const matchFilter = (activeFilter === "all") || (w.status.toLowerCase() === activeFilter);
    const matchSearch = w.id.toLowerCase().includes(searchVal) || w.type.toLowerCase().includes(searchVal);
    return matchFilter && matchSearch;
  });

  countEl.innerText = filtered.length;
  listEl.innerHTML = "";

  filtered.forEach(w => {
    const card = document.createElement("div");
    card.className = `workflow-card ${w.id === selectedWorkflow.id ? 'selected' : ''}`;
    
    let statusClass = "success";
    if (w.status === "RUNNING") statusClass = "running";
    if (w.status === "COMPENSATED") statusClass = "rollback";
    if (w.status === "FAILED") statusClass = "failed";

    card.innerHTML = `
      <div class="card-top">
        <span class="card-id">${w.id}</span>
        <span class="status-badge ${statusClass}">${w.status}</span>
      </div>
      <div class="card-type">${w.type}</div>
      <div class="card-bottom">
        <span>${w.duration}</span>
        <span>${w.eventsCount} events</span>
      </div>
    `;

    card.addEventListener("click", () => {
      selectedWorkflow = w;
      renderSidebar();
      renderWorkflowDetail();
    });

    listEl.appendChild(card);
  });
}

function renderWorkflowDetail() {
  const w = selectedWorkflow;

  document.getElementById("banner-id").innerText = w.id;
  document.getElementById("banner-type").innerText = w.type;
  
  const statusBadge = document.getElementById("banner-status");
  statusBadge.innerText = w.status;
  statusBadge.className = "status-badge";
  if (w.status === "COMPLETED") statusBadge.classList.add("success");
  if (w.status === "RUNNING") statusBadge.classList.add("running");
  if (w.status === "COMPENSATED") statusBadge.classList.add("rollback");
  if (w.status === "FAILED") statusBadge.classList.add("failed");

  document.getElementById("banner-duration").innerText = w.duration;
  document.getElementById("banner-events-count").innerText = w.eventsCount;
  document.getElementById("banner-compensated").innerText = w.compensated;

  renderPipeline(w);
  renderJournal(w.events);
  updateReplayControls(w.events);
}

function renderPipeline(w) {
  const canvas = document.getElementById("pipeline-canvas");
  canvas.innerHTML = "";

  w.steps.forEach((step, idx) => {
    const node = document.createElement("div");
    node.className = `step-node ${step.status}`;

    let compTagHtml = "";
    if (step.comp) {
      compTagHtml = `<div class="step-compensation-tag">↺ ${step.comp}</div>`;
    }

    node.innerHTML = `
      <div class="step-node-header">
        <span class="step-name">${step.name}</span>
        <span class="step-duration">${step.duration}</span>
      </div>
      ${compTagHtml}
    `;

    canvas.appendChild(node);

    if (idx < w.steps.length - 1) {
      const arrow = document.createElement("div");
      arrow.className = "arrow-connector";
      arrow.innerText = "➔";
      canvas.appendChild(arrow);
    }
  });
}

function renderJournal(events) {
  const tbody = document.getElementById("journal-tbody");
  tbody.innerHTML = "";

  events.forEach(evt => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>#${evt.id}</td>
      <td style="color: var(--accent-cyan); font-weight: 600;">${evt.type}</td>
      <td style="color: var(--text-muted);">${evt.ts}</td>
      <td style="color: #a5d6ff;">${JSON.stringify(evt.payload)}</td>
    `;
    tbody.appendChild(tr);
  });
}

function updateReplayControls(events) {
  const slider = document.getElementById("replay-slider");
  const stepVal = document.getElementById("replay-step-val");

  slider.max = events.length;
  slider.value = events.length;
  stepVal.innerText = events.length;

  updateReplayState(events.length);
}

function updateReplayState(stepIdx) {
  const w = selectedWorkflow;
  const sliced = w.events.slice(0, stepIdx);
  
  const reconstructed = {
    workflow_id: w.id,
    current_step: stepIdx,
    event_type: sliced[sliced.length - 1]?.type || "NONE",
    accumulated_state: {},
    journal_entries: sliced.length
  };

  sliced.forEach(e => {
    Object.assign(reconstructed.accumulated_state, e.payload);
  });

  document.getElementById("replay-state-json").innerText = JSON.stringify(reconstructed, null, 2);
}

function setupEventListeners() {
  // Filter buttons
  document.querySelectorAll(".filter-tab").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".filter-tab").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      activeFilter = btn.dataset.filter;
      renderSidebar();
    });
  });

  // Search input
  document.getElementById("workflow-search").addEventListener("input", renderSidebar);

  // Tab switching
  document.querySelectorAll(".tab-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
      document.querySelectorAll(".tab-pane").forEach(p => p.classList.remove("active"));

      btn.classList.add("active");
      document.getElementById(`pane-${btn.dataset.tab}`).classList.add("active");
    });
  });

  // Replay slider
  const slider = document.getElementById("replay-slider");
  slider.addEventListener("input", (e) => {
    const val = parseInt(e.target.value);
    document.getElementById("replay-step-val").innerText = val;
    updateReplayState(val);
  });

  document.getElementById("btn-step-back").addEventListener("click", () => {
    let val = parseInt(slider.value);
    if (val > 1) {
      val--;
      slider.value = val;
      document.getElementById("replay-step-val").innerText = val;
      updateReplayState(val);
    }
  });

  document.getElementById("btn-step-next").addEventListener("click", () => {
    let val = parseInt(slider.value);
    if (val < selectedWorkflow.events.length) {
      val++;
      slider.value = val;
      document.getElementById("replay-step-val").innerText = val;
      updateReplayState(val);
    }
  });

  document.getElementById("btn-replay-run").addEventListener("click", () => {
    slider.value = 1;
    document.getElementById("replay-step-val").innerText = 1;
    updateReplayState(1);

    let curr = 1;
    const interval = setInterval(() => {
      if (curr >= selectedWorkflow.events.length) {
        clearInterval(interval);
      } else {
        curr++;
        slider.value = curr;
        document.getElementById("replay-step-val").innerText = curr;
        updateReplayState(curr);
      }
    }, 250);
  });
}

function loadPrometheusMetrics() {
  const metricsSample = [
    "# HELP keelson_workflows_active Total currently executing fibers",
    "# TYPE keelson_workflows_active gauge",
    "keelson_workflows_active 12",
    "",
    "# HELP keelson_wal_bytes_total Total bytes written to append-only WAL",
    "# TYPE keelson_wal_bytes_total counter",
    "keelson_wal_bytes_total 104857600",
    "",
    "# HELP keelson_fiber_switch_latency_seconds Latency of cooperative yields",
    "# TYPE keelson_fiber_switch_latency_seconds histogram",
    'keelson_fiber_switch_latency_seconds_bucket{le="0.000001"} 18402',
    'keelson_fiber_switch_latency_seconds_bucket{le="0.000005"} 49201',
    'keelson_fiber_switch_latency_seconds_bucket{le="0.000010"} 50000',
    'keelson_fiber_switch_latency_seconds_bucket{le="+Inf"} 50000',
    "keelson_fiber_switch_latency_seconds_sum 0.0185",
    "keelson_fiber_switch_latency_seconds_count 50000",
    "",
    "# HELP keelson_sagas_compensated_total Total sagas that successfully rolled back",
    "# TYPE keelson_sagas_compensated_total counter",
    "keelson_sagas_compensated_total 14"
  ].join("\n");

  document.getElementById("raw-metrics-text").innerText = metricsSample;
}
