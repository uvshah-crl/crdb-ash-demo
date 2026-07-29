#!/usr/bin/env bash
# Executes all ASH demo queries against the cluster and displays results.
# Use this to run through the full demo or run individual queries.
#
# Usage:
#   ./scripts/05_run_ash_queries.sh          # run all queries
#   ./scripts/05_run_ash_queries.sh 01       # run query 01 only
#   ./scripts/05_run_ash_queries.sh 07       # run query 07 only

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config
init_deploy_mode

QUERIES_DIR="${PROJECT_DIR}/sql/ash_queries"

run_query() {
    local sql_file="$1"
    local filename
    filename=$(basename "$sql_file")

    echo
    echo "================================================================"
    echo "  $filename"
    echo "================================================================"

    # Print the query comment header (lines starting with --)
    grep '^--' "$sql_file" | head -5
    echo "----------------------------------------------------------------"

    # Execute the SQL
    local sql
    sql=$(grep -v '^--' "$sql_file" | tr '\n' ' ')
    run_on_node 1 sql --insecure -e "$sql"

    echo
}

TARGET="${1:-}"

if [[ -n "$TARGET" ]]; then
    # Run a specific query by number prefix
    match=$(find "$QUERIES_DIR" -name "${TARGET}_*.sql" -o -name "${TARGET}.sql" 2>/dev/null | head -1)
    if [[ -z "$match" ]]; then
        log_error "No query file found matching: ${TARGET}"
        log_info "Available queries:"
        ls -1 "$QUERIES_DIR"/*.sql 2>/dev/null
        exit 1
    fi
    run_query "$match"
else
    # Run all queries in order
    for sql_file in "$QUERIES_DIR"/*.sql; do
        run_query "$sql_file"
        read -rp "Press Enter for next query (or Ctrl+C to stop)..." </dev/tty || true
    done
fi

echo "=== ASH Demo Queries Complete ==="
