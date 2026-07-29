#!/usr/bin/env bash
# Sets up schemas for all 3 workloads on the cluster.
# Runs sequentially: flight-schedules, train-events, point-lookup.
#
# Usage: ./scripts/01_setup_schemas.sh

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config
init_deploy_mode

WORKLOADS=("flight-schedules" "train-events" "point-lookup")

log_info "=== Setting up schemas for all workloads ==="

for WORKLOAD in "${WORKLOADS[@]}"; do
    WORKLOAD_DB=$(get_workload_database "$WORKLOAD")
    WORKLOAD_DIR="${PROJECT_DIR}/workloads/${WORKLOAD}"

    log_info "--- Setting up: $WORKLOAD (database: $WORKLOAD_DB) ---"

    if [[ ! -d "$WORKLOAD_DIR" ]]; then
        log_error "Workload directory not found: $WORKLOAD_DIR"
        exit 1
    fi

    SCHEMA_FILE="${WORKLOAD_DIR}/initial-schema.sql"
    POPULATE_FILE="${WORKLOAD_DIR}/populate-sample-data.sql"

    if [[ ! -f "$SCHEMA_FILE" ]]; then
        log_error "Schema file not found: $SCHEMA_FILE"
        exit 1
    fi

    log_info "Uploading schema files for $WORKLOAD..."
    put_file "$SCHEMA_FILE" "/tmp/${WORKLOAD}-schema.sql" 1

    if [[ -f "$POPULATE_FILE" ]]; then
        put_file "$POPULATE_FILE" "/tmp/${WORKLOAD}-populate.sql" 1
    fi

    log_info "Creating schema for $WORKLOAD..."
    run_on_node 1 sql --insecure -f "/tmp/${WORKLOAD}-schema.sql"

    if [[ -f "$POPULATE_FILE" ]]; then
        log_info "Populating sample data for $WORKLOAD (this may take a few minutes)..."
        run_on_node 1 sql --insecure -d "$WORKLOAD_DB" -f "/tmp/${WORKLOAD}-populate.sql"
    fi

    log_info "Verifying $WORKLOAD schema..."
    run_on_node 1 sql --insecure -d "$WORKLOAD_DB" -e 'SHOW TABLES;'

    log_info "--- $WORKLOAD schema complete ---"
    echo
done

log_info "=== All schemas set up ==="
