#!/usr/bin/env bash
# Creates, stages, and starts a CockroachDB v26.2 cluster.
# Supports both roachprod (AWS) and Docker/Podman Compose.
# Enables ASH and applies cluster settings.
#
# Usage: ./scripts/00_setup_cluster.sh

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config
ensure_prerequisites

apply_cluster_settings() {
    log_info "Applying cluster settings (enabling ASH)..."
    local local_settings="${PROJECT_DIR}/sql/cluster-settings.sql"
    if [[ -f "$local_settings" ]]; then
        put_file "$local_settings" /tmp/cluster-settings.sql 1
        run_on_node 1 sql --insecure -f /tmp/cluster-settings.sql
    else
        log_warn "sql/cluster-settings.sql not found, skipping"
    fi
}

verify_ash() {
    log_info "Verifying ASH is enabled..."
    run_on_node 1 sql --insecure -e 'SHOW CLUSTER SETTING obs.ash.enabled;'
}

if [[ "$DEPLOY_MODE" == "docker" ]]; then
    log_info "=== Setting up local CockroachDB cluster via Docker ==="
    log_info "Version: $CRDB_VERSION | Nodes: $NUM_NODES"

    docker_compose_up
    wait_for_cluster_ready
    apply_cluster_settings
    verify_ash

    log_info "=== Cluster is ready ==="
    log_info "Admin UI: http://localhost:26258"
    log_info "HAProxy stats: http://localhost:8404"
    log_info "SQL URL (via HAProxy): postgres://root@localhost:${HAPROXY_PORT}/defaultdb?sslmode=disable"
    log_info "SQL CLI: $CONTAINER_RUNTIME exec -it crdb-1 /cockroach/cockroach sql --insecure"

else
    derive_aws_identity
    fetch_rev_json

    log_info "=== Setting up CockroachDB cluster for ASH Demo ==="
    log_info "Cloud: $CLOUD | Version: $CRDB_VERSION | Nodes: $NUM_NODES | Machine: $AWS_MACHINE_TYPE"

    # ---- Create ----
    log_info "Creating cluster: $CLUSTER"
    roachprod --aws-profile "$PROFILE" create "$CLUSTER" \
        -n "$NUM_NODES" \
        --clouds=aws \
        --aws-config="$REV_JSON" \
        --aws-machine-type-ssd="$AWS_MACHINE_TYPE" \
        --lifetime="$CLUSTER_LIFETIME" \
        || log_warn "Create may have shown a nil pointer panic — known bug. EC2 instances are created. Proceeding."

    # ---- Stage ----
    log_info "Staging CockroachDB $CRDB_VERSION"
    roachprod stage "$CLUSTER" release "$CRDB_VERSION"

    # ---- Start ----
    log_info "Starting cluster"
    roachprod --aws-profile "$PROFILE" start "$CLUSTER" --insecure

    # ---- Wait for ready ----
    wait_for_cluster_ready

    # ---- Apply cluster settings (including ASH) ----
    apply_cluster_settings
    verify_ash

    # ---- Start local HAProxy ----
    start_haproxy

    # ---- Print access info ----
    log_info "=== Cluster is ready ==="

    EXTERNAL_IP=$(roachprod ip "${CLUSTER}:1" --external 2>/dev/null)
    log_info "Admin UI: http://${EXTERNAL_IP}:26258"
    log_info "HAProxy stats: http://localhost:8404"
    log_info "SQL URL (via HAProxy): postgres://root@localhost:${HAPROXY_PORT}/defaultdb?sslmode=disable"

    PGURL=$(roachprod pgurl "${CLUSTER}:1" --insecure 2>/dev/null)
    log_info "SQL URL (direct node 1): $PGURL"

    log_info "SSH:     roachprod ssh ${CLUSTER}:1"
    log_info "SQL:     roachprod sql ${CLUSTER}:1 --insecure"
    log_info "Status:  roachprod --aws-profile $PROFILE status $CLUSTER"
    log_info "Extend:  roachprod --aws-profile $PROFILE extend $CLUSTER --lifetime=$CLUSTER_LIFETIME"
fi
