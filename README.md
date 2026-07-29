# CockroachDB Active Session History (ASH) Demo

Live demo of CockroachDB's Active Session History feature (preview in v26.2). Deploys a cluster, runs realistic workloads that generate diverse work events (CPU, IO, lock contention, admission queuing, background jobs), then explores ASH data through SQL queries and Grafana dashboards.

## Dashboard Preview

<!-- Replace with your screen recording converted to GIF -->
![ASH Dashboard](docs/ash-demo.gif)

## Prerequisites

- **roachprod** (for AWS deployment) or **Docker/Podman** (for local deployment)
- **AWS CLI** with SSO configured (roachprod mode)
- **HAProxy** — `brew install haproxy`
- **dbworkload** — `pip install 'dbworkload[postgres]'`
- **Docker** (for Grafana container)

For a detailed step-by-step walkthrough with SQL examples and talking points, see the [Demo Runbook](docs/RUNBOOK.md).

## Quick Start

```bash
# 0. Check and install prerequisites (macOS)
./scripts/install_prerequisites.sh

# 1. Create cluster, enable ASH, start HAProxy
./scripts/00_setup_cluster.sh

# 2. Create schemas for all workloads
./scripts/01_setup_schemas.sh

# 3. Start workloads (flight-schedules, train-events, point-lookup)
./scripts/02_start_workloads.sh all

# 4. Start background backup jobs (generates JOB work events)
./scripts/03_start_background_jobs.sh loop

# 5. Run ASH SQL queries interactively
./scripts/05_run_ash_queries.sh

# 6. Launch Grafana dashboards
./scripts/06_start_grafana.sh
```

## Configuration

Edit `config.env` to switch between deploy modes or adjust cluster settings:

| Setting | Default | Description |
|---|---|---|
| `DEPLOY_MODE` | `roachprod` | `roachprod` (AWS) or `docker` (local) |
| `CRDB_VERSION` | `v26.2.0` | CockroachDB version |
| `NUM_NODES` | `3` | Cluster size |
| `AWS_MACHINE_TYPE` | `m5d.2xlarge` | EC2 instance type |
| `WORKLOAD_CONCURRENCY` | `8` | Concurrent workers per workload |
| `WORKLOAD_DURATION_SECONDS` | `1800` | Workload run time |

## Workloads

| Workload | App Name | Database | What It Generates |
|---|---|---|---|
| **flight-schedules** | `flight_schedule_updater` | defaultdb | Write-heavy UPDATEs across 4 tables — CPU and IO work events |
| **train-events** | `train_event_pipeline` | defaultdb | JSONB pipeline with `SELECT FOR UPDATE SKIP LOCKED` — lock contention events |
| **point-lookup** | `outbox_processor` | hotspot | Outbox pattern with 50KB payloads — mixed IO/CPU work events |
| **backup jobs** | (system) | defaultdb | Periodic `BACKUP` — JOB work events in ASH |

## ASH Queries

12 progressive SQL queries in `sql/ash_queries/`:

| # | Query | Focus |
|---|---|---|
| 01 | Raw samples | Verify ASH is collecting data |
| 02 | Work event breakdown | Distribution across CPU, IO, LOCK, etc. |
| 03 | Work event detail | Drill into specific event types |
| 04 | Workload type | User SQL vs system vs internal |
| 05 | App-level analysis | Per-application_name breakdown |
| 06 | Node drill-down | Per-node work event distribution |
| 07 | Lock contention | Contention hot spots and wait times |
| 08 | Job analysis | Background job work events |
| 09 | Admission analysis | Admission control queue impact |
| 10 | Time series | Work events over time |
| 11 | System internals | Internal CockroachDB operations |
| 12 | Statement fingerprint | Per-statement work event profiles |

Run individually: `./scripts/05_run_ash_queries.sh 07`

## Grafana Dashboards

Start Grafana on port 3001: `./scripts/06_start_grafana.sh`

| Dashboard | URL Path | Description |
|---|---|---|
| ASH Overview | `/d/ash-overview` | Work events by type, application, and node over time |
| Lock Detail | `/d/ash-lock-detail` | Lock contention drill-down |
| Job Detail | `/d/ash-job-detail` | Background job work events |
| Admission Detail | `/d/ash-admission-detail` | Admission control queue analysis |
| Statement Detail | `/d/ash-statement-detail` | Per-statement work event profiles |

## Teardown

```bash
./scripts/04_stop_workloads.sh        # stop dbworkload processes
./scripts/06_start_grafana.sh stop    # stop Grafana container
./scripts/99_teardown_cluster.sh      # destroy cluster
```

## Project Structure

```
├── config.env                  # Cluster and workload configuration
├── compose.yml                 # Docker Compose for local mode
├── scripts/                    # All lifecycle scripts
├── sql/
│   ├── cluster-settings.sql    # ASH cluster settings
│   └── ash_queries/            # 12 demo SQL queries
├── workloads/
│   ├── flight-schedules/       # Write-heavy workload
│   ├── train-events/           # Lock contention workload
│   └── point-lookup/           # Mixed IO/CPU workload
├── grafana/
│   ├── dashboards/             # 5 ASH dashboard JSONs
│   └── provisioning/           # Grafana datasource configs
└── docs/
    └── RUNBOOK.md              # Step-by-step demo walkthrough
```
