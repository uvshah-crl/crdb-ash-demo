#!/usr/bin/env bash
# Stops all running background workloads started by 02_start_workloads.sh.
#
# Usage:
#   ./scripts/04_stop_workloads.sh              # stop all
#   ./scripts/04_stop_workloads.sh flight-schedules  # stop one

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config

stop_workload() {
    local workload="$1"
    local pid
    pid=$(get_pid "$workload")

    if [[ -z "$pid" ]]; then
        log_info "$workload: no PID file found (not running or already stopped)"
        return
    fi

    if kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping $workload (PID $pid)..."
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        log_info "$workload stopped"
    else
        log_info "$workload: process $pid already exited"
    fi

    remove_pid "$workload"
}

TARGET="${1:-all}"

if [[ "$TARGET" == "all" ]]; then
    stop_workload "flight-schedules"
    stop_workload "train-events"
    stop_workload "point-lookup"
else
    stop_workload "$TARGET"
fi

log_info "=== Workloads stopped ==="
