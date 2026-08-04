#!/usr/bin/env bash
# Starts a workload in the background for the ASH demo.
# Each workload runs with a distinct application_name so ASH can distinguish them.
#
# Usage:
#   ./scripts/02_start_workloads.sh flight-schedules
#   ./scripts/02_start_workloads.sh train-events
#   ./scripts/02_start_workloads.sh point-lookup
#   ./scripts/02_start_workloads.sh all          # start all 3

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config
ensure_dbworkload
init_deploy_mode
ensure_haproxy

LOGS_DIR="${PROJECT_DIR}/logs"
mkdir -p "$LOGS_DIR"

start_workload() {
    local workload="$1"
    local db
    db=$(get_workload_database "$workload")
    local txn_file
    txn_file=$(get_workload_file "$workload")
    local args
    args=$(get_workload_args "$workload")

    # Derive application_name from workload (e.g. flight-schedules -> flight_schedules)
    local app_name
    app_name=$(echo "$workload" | tr '-' '_')

    local pgurl
    pgurl=$(get_pgurl "$db" "$app_name")

    local log_file="${LOGS_DIR}/${workload}_$(date '+%Y%m%d_%H%M%S').log"

    # Check if already running
    local existing_pid
    existing_pid=$(get_pid "$workload")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        log_warn "$workload is already running (PID $existing_pid)"
        return
    fi

    log_info "Starting $workload (app_name=$app_name, cc=$WORKLOAD_CONCURRENCY, dur=${WORKLOAD_DURATION_SECONDS}s)"
    log_info "  Database: $db | File: $txn_file"
    log_info "  Log: $log_file"

    nohup dbworkload run \
        -w "${PROJECT_DIR}/workloads/${workload}/${txn_file}" \
        -a "$app_name" \
        -c "$WORKLOAD_CONCURRENCY" \
        -d "$WORKLOAD_DURATION_SECONDS" \
        --procs 1 \
        --uri "$pgurl" \
        --args "$args" \
        > "$log_file" 2>&1 &

    local pid=$!
    save_pid "$workload" "$pid"
    log_info "$workload started (PID $pid)"
}

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <workload|all>"
    echo "  workload: flight-schedules, train-events, point-lookup"
    echo "  all:      start all 3 workloads"
    exit 1
fi

if [[ "$TARGET" == "all" ]]; then
    start_workload "flight-schedules"
    start_workload "train-events"
    start_workload "point-lookup"
else
    start_workload "$TARGET"
fi

log_info "=== Workloads started. Run ASH queries while they execute. ==="
