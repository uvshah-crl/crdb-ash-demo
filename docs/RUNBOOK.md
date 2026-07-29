# ASH Demo Runbook

## Overview

This runbook walks through a live demo of CockroachDB's Active Session History (ASH) feature.

**Cluster:** 3-node CockroachDB v26.2.0 on AWS (m5d.2xlarge) or local Docker/Podman
**Workloads:** flight-schedules (write-heavy), train-events (contention), point-lookup (mixed)
**Duration:** ~15 minutes for the live demo portion

---

## Deploy Modes

The demo supports two deploy modes, configured via `DEPLOY_MODE` in `config.env`:

### Docker/Podman (default — `DEPLOY_MODE="docker"`)

Runs a 3-node CockroachDB cluster locally using Docker Compose or Podman Compose. No AWS account or roachprod needed.

**Prerequisites:**
- Docker Desktop (with `docker compose`) or Podman (with `podman compose`)
- `dbworkload` Python package: `pip install 'dbworkload[postgres]'`

**Access:**
- SQL (via HAProxy): `postgres://root@localhost:26000/defaultdb?sslmode=disable`
- Admin UI: `http://localhost:26258`
- HAProxy stats: `http://localhost:8404`
- SQL CLI: `docker exec -it crdb-1 /cockroach/cockroach sql --insecure`

The scripts auto-detect whether `podman` or `docker` is available (checks podman first).

### Roachprod (`DEPLOY_MODE="roachprod"`)

Runs a 3-node cluster on AWS via `roachprod` (Cockroach Labs internal tool). HAProxy runs locally on your Mac to load-balance connections across all nodes.

**Prerequisites:**
- `roachprod` on PATH
- AWS CLI configured with SSO profile for crl-dev-revenue
- `haproxy`: `brew install haproxy`
- `dbworkload` Python package

**Access:**
- SQL (via HAProxy): `postgres://root@localhost:26000/defaultdb?sslmode=disable`
- HAProxy stats: `http://localhost:8404`
- Admin UI: `http://<node-1-ip>:26258`

All scripts work identically in both modes — the abstraction layer in `_common.sh` handles the dispatch.

### Cluster name persistence

After `00_setup_cluster.sh` runs, the cluster name is saved to `.cluster_name`. All subsequent scripts read from this file, avoiding repeated AWS identity lookups. The name is also exported as `ASH_DEMO_CLUSTER`.

---

## Pre-Demo Setup (Day Before)

### 1. Create cluster and enable ASH

```bash
./scripts/00_setup_cluster.sh
```

This creates the roachprod cluster, starts CockroachDB, and enables ASH via cluster settings.

### 2. Set up all workload schemas

```bash
./scripts/01_setup_schemas.sh
```

Creates tables and populates data for all 3 workloads.

### 3. Verify ASH is active

Connect to the cluster and confirm:

```bash
./scripts/05_run_ash_queries.sh 01
# Should return ASH sample rows
```

Or directly via the saved cluster name:

```bash
roachprod run $(cat .cluster_name):1 -- "./cockroach sql --insecure -e \"SHOW CLUSTER SETTING obs.ash.enabled;\""
# Should return: true
```

### 4. Dry-run workloads and queries

Start a workload briefly to confirm ASH data flows:

```bash
./scripts/02_start_workloads.sh flight-schedules
sleep 30
./scripts/05_run_ash_queries.sh 01
./scripts/04_stop_workloads.sh
```

You should see rows in the ASH query output with `app_name = 'flight_schedules'`.

### 5. Note the DB Console URL

```bash
roachprod adminurl <cluster>:1 --insecure
```

Keep this open in a browser tab during the demo.

---

## Demo Flow (~15 minutes)

### Step 1 — Show ASH is Enabled (30s)

```sql
SHOW CLUSTER SETTING obs.ash.enabled;
-- true

SHOW CLUSTER SETTING obs.ash.sample_interval;
-- 00:00:01 (1 second)

SHOW CLUSTER SETTING obs.ash.buffer_size;
-- 1000000 (1M samples per node, ~15-20 min at moderate load)
```

ASH is enabled with a single cluster setting. It samples every second, stores up to 1M samples per node in a circular in-memory buffer. No external tooling needed — you query it with SQL.

---

### Step 2 — Start flight-schedules Workload (30s)

```bash
./scripts/02_start_workloads.sh flight-schedules
```

Starting a write-heavy workload that simulates airline flight operations — UPDATEs against 1M flight rows. This runs in the background while we query ASH.

Wait ~30 seconds for data to accumulate.

---

### Step 3 — Raw ASH Samples (1 min)

```bash
./scripts/05_run_ash_queries.sh 01
```

```sql
-- sql/ash_queries/01_raw_samples.sql
SELECT
    sample_time,
    node_id,
    workload_type,
    workload_id,
    app_name,
    work_event_type,
    work_event
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '2 minutes'
ORDER BY sample_time DESC
LIMIT 20;
```

Each row is a single-second snapshot of active work on the cluster. You see the timestamp, which node, what type of work, the application name, and what resource it was using at that moment.

---

### Step 4 — Work Event Type Breakdown (2 min)

```bash
./scripts/05_run_ash_queries.sh 02
```

```sql
-- sql/ash_queries/02_work_event_breakdown.sql
SELECT
    work_event_type,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
GROUP BY work_event_type
ORDER BY samples DESC;
```

This is the work event type breakdown. CPU, IO, LOCK, NETWORK, ADMISSION. Count the rows to get "database seconds" — the number of samples equals the number of seconds of active work.

Then drill into CPU:

```bash
./scripts/05_run_ash_queries.sh 03
```

```sql
-- sql/ash_queries/03_work_event_detail.sql
SELECT
    work_event,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
  AND work_event_type = 'CPU'
GROUP BY work_event
ORDER BY samples DESC
LIMIT 15;
```

If CPU is dominant, drill in to see what's consuming it — tablereader (scanning data), upsert (writing), Optimize (query planning), hashJoiner (join execution).

---

### Step 5 — App-Level Analysis (1 min)

```bash
./scripts/05_run_ash_queries.sh 05
```

```sql
-- sql/ash_queries/05_app_level.sql
SELECT
    app_name,
    work_event_type,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
  AND workload_type = 'STATEMENT'
GROUP BY app_name, work_event_type
ORDER BY samples DESC;
```

Each workload connects with a distinct application_name. Right now you see flight_schedules dominating. When we add more workloads, you'll see them appear separately — no guessing which app is doing what.

---

### Step 6 — Start train-events Workload (30s)

```bash
./scripts/02_start_workloads.sh train-events
```

Adding a second workload — an event processing pipeline that uses `SELECT FOR UPDATE SKIP LOCKED`. This deliberately creates lock contention.

Wait ~30 seconds.

---

### Step 7 — Lock Contention Analysis (2 min)

```bash
./scripts/05_run_ash_queries.sh 07
```

```sql
-- sql/ash_queries/07_lock_contention.sql
SELECT
    work_event,
    app_name,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
  AND work_event_type = 'LOCK'
GROUP BY work_event, app_name
ORDER BY samples DESC;
```

Now we see LOCK events appearing — LockWait, TxnPushWait. And look at the app_name: it's train_events. The flight-schedules workload isn't generating lock contention. ASH tells you exactly which application has the problem.

Re-run app-level to show both apps side by side:

```bash
./scripts/05_run_ash_queries.sh 05
```

---

### Step 8 — Start Background BACKUP Job (30s)

```bash
./scripts/03_start_background_jobs.sh
```

Kicking off a BACKUP job. In production, backups run alongside your OLTP workload. The question is: how much resource is the backup consuming vs your application?

---

### Step 9 — STATEMENT vs JOB Separation (2 min)

```bash
./scripts/05_run_ash_queries.sh 04
```

```sql
-- sql/ash_queries/04_workload_type.sql
SELECT
    workload_type,
    work_event_type,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
GROUP BY workload_type, work_event_type
ORDER BY samples DESC;
```

Workload is separated by TYPE — STATEMENT is user SQL, JOB is the backup, SYSTEM is internal CockroachDB work like Raft consensus and garbage collection. All in one view, so you can immediately see who's consuming resources.

Then drill into the backup job:

```bash
./scripts/05_run_ash_queries.sh 08
```

```sql
-- sql/ash_queries/08_job_analysis.sql
SELECT
    workload_id AS job_id,
    work_event_type,
    work_event,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
  AND workload_type = 'JOB'
GROUP BY workload_id, work_event_type, work_event
ORDER BY samples DESC;
```

Drill into the BACKUP job specifically — you see its CPU and IO breakdown. If your OLTP latency spiked while a backup was running, this is how you prove it.

---

### Step 10 — Node Drilldown (1 min)

```bash
./scripts/05_run_ash_queries.sh 06
```

```sql
-- sql/ash_queries/06_node_drilldown.sql
SELECT
    node_id,
    work_event_type,
    app_name,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
GROUP BY node_id, work_event_type, app_name
ORDER BY node_id, samples DESC;
```

Incident scenario: you get paged at 2 AM because Node 2 CPU is at 90%. Instead of guessing, you filter ASH by node_id and time range. Instantly see which app, which work event, which workload type was responsible.

---

### Step 11 — Time Series Trends (1 min)

```bash
./scripts/05_run_ash_queries.sh 10
```

```sql
-- sql/ash_queries/10_time_series.sql
SELECT
    date_trunc('minute', sample_time) AS minute,
    work_event_type,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
GROUP BY minute, work_event_type
ORDER BY minute DESC, samples DESC;
```

Bucket by minute to see how the workload profile evolved. You can see when each workload started, when the backup kicked in, how the CPU/LOCK/IO mix shifted. This is the foundation for building a Grafana or Datadog dashboard on top of ASH.

---

### Step 12 — System Internals (1 min)

```bash
./scripts/05_run_ash_queries.sh 11
```

```sql
-- sql/ash_queries/11_system_internals.sql
SELECT
    workload_id AS system_task,
    work_event_type,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
  AND workload_type = 'SYSTEM'
GROUP BY workload_id, work_event_type
ORDER BY samples DESC
LIMIT 15;
```

CockroachDB exposes its own internal work in ASH. You can see Raft consensus, garbage collection, intent resolution, range feeds. This is useful when you're troubleshooting: is the cluster slow because of my SQL, or because of internal maintenance?

---

### Step 13 — Admission Control (1 min, if ADMISSION events present)

```bash
./scripts/05_run_ash_queries.sh 09
```

```sql
-- sql/ash_queries/09_admission_analysis.sql
SELECT
    work_event,
    app_name,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
  AND work_event_type = 'ADMISSION'
GROUP BY work_event, app_name
ORDER BY samples DESC;
```

ADMISSION is CockroachDB's built-in flow control. When the cluster is under pressure, it queues work instead of letting everything through. High ADMISSION counts aren't a bug — they mean the system is protecting itself. But it's a signal you might be running hot.

---

### Step 14 — Statement Fingerprint Join (2 min)

```bash
./scripts/05_run_ash_queries.sh 12
```

```sql
-- sql/ash_queries/12_statement_fingerprint.sql
SELECT
    ash.workload_id,
    substring(ss.metadata->>'query', 1, 80) AS query_preview,
    ash.work_event_type,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history ash
JOIN crdb_internal.statement_statistics ss
    ON ash.workload_id = encode(ss.fingerprint_id, 'hex')
WHERE ash.workload_type = 'STATEMENT'
  AND ash.sample_time > now() - INTERVAL '30 minutes'
GROUP BY ash.workload_id, query_preview, ash.work_event_type
ORDER BY samples DESC
LIMIT 20;
```

ASH's `workload_id` for statements is the hex-encoded fingerprint ID — the same one in `crdb_internal.statement_statistics`. Join them and you get the actual SQL text alongside the resource breakdown. Now you know not just that CPU is high, but exactly which query is responsible.

---

### Summary (2 min)

**What ASH gives you today:**
- Second-by-second sampling of all active work
- CPU, IO, LOCK, NETWORK, ADMISSION breakdown
- App-level, node-level, workload-type filtering
- Cluster-wide view via SQL
- Debug zip integration

**Current limitations:**
- In-memory only — buffer rolls over (no built-in persistence)
- No plan gist or query text in the sample (join with statement_statistics)
- No blocker session identity
- Not recommended for nodes with 64+ vCPUs

**Workaround for persistence:** Set up a scheduled extract to push ASH samples to your time-series DB or data warehouse every few minutes.

---

## Grafana Dashboard

The ASH dashboard provides a real-time graphical view of ASH data.

### Docker mode

Grafana starts automatically with `docker compose up`. Access:

- **Dashboard:** http://localhost:3000/d/ash-overview
- **Login:** anonymous access enabled (no login needed)

### Roachprod mode

Start Grafana as a standalone container:

```bash
./scripts/06_start_grafana.sh start
```

Stop it:

```bash
./scripts/06_start_grafana.sh stop
```

### Dashboard Panels

| Row | Panel | Type | Question Answered |
|---|---|---|---|
| Header | Total Samples / Active Apps / Lock % / Admission % | Stat | Health at a glance |
| Overview | Active Sessions by Wait Class | Stacked area | "What's consuming resources?" |
| Overview | Current Wait Class Distribution | Donut pie | Resource mix right now |
| Workload | STATEMENT vs JOB vs SYSTEM | Stacked area | "Is it user SQL, jobs, or system?" |
| Workload | Samples by Application | Bar chart | "Which application is the problem?" |
| Node & Lock | Per-Node Distribution | Bar chart | "Which node is hot?" |
| Node & Lock | Lock Contention | Table | "Where's the lock contention?" |
| Top SQL | Top SQL by ASH Samples | Table | "What SQL is causing this?" |
| Background | Admission Control | Time series | "Is admission throttling?" |
| Background | System Internals | Bar chart | "What's the system doing?" |
| Background | Job Analysis | Bar chart | "What's the backup consuming?" |

Use the **Node** and **Application** dropdowns at the top to filter all panels.

---

## Post-Demo Cleanup

```bash
./scripts/04_stop_workloads.sh
./scripts/99_teardown_cluster.sh
```

---

## Quick Reference: ASH Settings

| Setting | Default | Description |
|---|---|---|
| `obs.ash.enabled` | false | Enable/disable ASH |
| `obs.ash.sample_interval` | 1s | Sampling frequency |
| `obs.ash.buffer_size` | 1,000,000 | Max samples per node (~200 bytes each) |
| `obs.ash.log_interval` | 10m | Periodic summary to OPS log |
| `obs.ash.response_limit` | 10,000 | Max samples per node for cluster-wide queries |

## Quick Reference: ASH Views

| View | Scope |
|---|---|
| `information_schema.crdb_node_active_session_history` | Gateway node only (uncapped) |
| `information_schema.crdb_cluster_active_session_history` | All nodes (capped by response_limit) |

## Quick Reference: Work Event Types

| Type | Meaning |
|---|---|
| CPU | Actively computing |
| IO | Storage I/O |
| LOCK | Row lock / latch wait |
| NETWORK | Cross-node RPC |
| ADMISSION | Flow control queue |
| OTHER | Raft proposals, backpressure, etc. |

## Quick Reference: Work Event Samples

> **Note:** These are event samples observed from the workloads in this demo, not a comprehensive list of all possible CockroachDB work events.

### IO

| Event | Description |
|---|---|
| KVEval | KV replica evaluation (IO tag is approximate — may be cache hit) |

### NETWORK

| Event | Description |
|---|---|
| DistSenderRemote | Waiting for remote node (network hop in distributed query) |
| InboxRecv | Waiting for DistSQL data stream from remote node |

### CPU

| Event | Description |
|---|---|
| DistSenderLocal | Local KV dispatch (on CPU, same node) |
| Optimize | Query optimizer running |
| ReplicaSend | Replica layer processing KV request |
| BatchFlowCoordinator | Vectorized DistSQL coordinator on CPU |
| materializer | Columnar-to-row conversion (end of vectorized pipeline) |
| table reader | Table/index scan |
| scan buffer | Buffering scan results |
| buffer | Generic row buffer |
| columnarizer | Row-to-columnar conversion (start of vectorized pipeline) |
| join reader | Index/lookup join |
| projectSet | SRF / lateral join processor |
| noop | No-op pass-through |
| insert / update / upsert | DML processors |
| virtual table | crdb_internal / information_schema scan (includes ASH querying itself) |

### LOCK

| Event | Description |
|---|---|
| LatchWait | Range-level concurrency control (short-lived) |
| LockWait | Row lock contention (blocked by another txn) |

### OTHER

| Event | Description |
|---|---|
| RaftProposalWait | Write waiting for Raft quorum |

### JOB-related (CPU/IO)

| Event | Description |
|---|---|
| backupDataProcessor | BACKUP job data export |
| sample aggregator | Stats histogram aggregation |
| sampler | Auto-stats row sampling |
| create statistics | Stats job execution |

### ADMISSION

| Event | Description |
|---|---|
| kv-elastic-cpu-queue | Elastic CPU throttling (background work waiting for CPU token) |
