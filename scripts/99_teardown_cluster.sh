#!/usr/bin/env bash
# Destroys the cluster. For roachprod: destroys AWS instances.
# For Docker: stops containers and removes volumes.
#
# Usage: ./scripts/99_teardown_cluster.sh

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config

# Stop any running workloads and HAProxy first
"${SCRIPT_DIR}/04_stop_workloads.sh" || true
stop_haproxy

if [[ "$DEPLOY_MODE" == "docker" ]]; then
    detect_container_runtime

    log_info "=== Tearing down local Docker cluster ==="
    read -rp "Are you sure you want to destroy the local cluster? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Aborted."
        exit 0
    fi

    docker_compose_down
    rm -f "$CLUSTER_NAME_FILE"
    log_info "Local cluster destroyed."

else
    derive_aws_identity

    log_info "=== Destroying cluster: $CLUSTER ==="
    read -rp "Are you sure you want to destroy cluster '$CLUSTER'? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Aborted."
        exit 0
    fi

    roachprod --aws-profile "$PROFILE" destroy "$CLUSTER"
    rm -f "$CLUSTER_NAME_FILE"
    log_info "Cluster $CLUSTER destroyed."
fi
