#!/usr/bin/env bash
# Starts background jobs on the cluster to generate workload_type = 'JOB'
# samples in ASH. This demonstrates ASH's ability to separate user SQL from
# background jobs.
#
# Usage:
#   ./scripts/03_start_background_jobs.sh          # run all jobs
#   ./scripts/03_start_background_jobs.sh backup    # single backup
#   ./scripts/03_start_background_jobs.sh loop      # recurring backups

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config
init_deploy_mode

LOGS_DIR="${PROJECT_DIR}/logs"
mkdir -p "$LOGS_DIR"

setup_backup_table() {
    log_info "Creating backup source table..."
    run_on_node 1 sql --insecure -e "
CREATE TABLE IF NOT EXISTS defaultdb.backup_source (
    id INT PRIMARY KEY DEFAULT unique_rowid(),
    data STRING DEFAULT repeat('x', 1000),
    ts TIMESTAMPTZ DEFAULT now()
);
INSERT INTO defaultdb.backup_source (data)
SELECT repeat(chr(65 + (i % 26)::INT), 1000)
FROM generate_series(1, 10000) AS g(i)
ON CONFLICT DO NOTHING;
"
}

run_backup() {
    local label="${1:-manual}"
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    log_info "Starting BACKUP (${label})..."
    run_on_node 1 sql --insecure -e "
BACKUP DATABASE defaultdb INTO 'nodelocal://1/ash-demo-backup/${ts}' WITH detached;
"
    log_info "BACKUP job submitted (${label}, ts=${ts})."
}

run_backup_loop() {
    local interval="${1:-120}"
    local count="${2:-10}"
    local log_file="${LOGS_DIR}/backup_loop_$(date '+%Y%m%d_%H%M%S').log"

    log_info "Starting recurring backup loop (every ${interval}s, ${count} iterations)"
    log_info "  Log: $log_file"

    nohup bash -c "
        for i in \$(seq 1 ${count}); do
            echo \"[\$(date '+%H:%M:%S')] Backup iteration \$i/${count}\"
            $(printf '%q ' roachprod run "$(cat "${PROJECT_DIR}/.cluster_name"):1" -- \
                "./cockroach sql --insecure -e \"BACKUP DATABASE defaultdb INTO 'nodelocal://1/ash-demo-backup/loop_\$i' WITH detached;\"")
            echo \"[\$(date '+%H:%M:%S')] Backup \$i submitted, sleeping ${interval}s\"
            sleep ${interval}
        done
        echo \"[\$(date '+%H:%M:%S')] Backup loop complete\"
    " > "$log_file" 2>&1 &

    local pid=$!
    save_pid "backup-loop" "$pid"
    log_info "Backup loop started (PID $pid)"
}

TARGET="${1:-all}"

case "$TARGET" in
    backup)
        setup_backup_table
        run_backup "single"
        ;;
    loop)
        setup_backup_table
        run_backup_loop 120 10
        ;;
    all)
        setup_backup_table
        run_backup "initial"
        run_backup_loop 120 10
        ;;
    *)
        echo "Usage: $0 [backup|loop|all]"
        exit 1
        ;;
esac

log_info "=== Background jobs started. Check ASH for workload_type = 'JOB' samples. ==="
log_info "Run: ./scripts/05_run_ash_queries.sh 04"
