#!/usr/bin/env bash
# Starts a standalone Grafana container for ASH dashboard visualization.
# For use in roachprod mode where Docker Compose is not used.
#
# Usage:
#   ./scripts/06_start_grafana.sh          # start
#   ./scripts/06_start_grafana.sh start    # start
#   ./scripts/06_start_grafana.sh stop     # stop and remove container

set -euo pipefail
source "$(dirname "$0")/_common.sh"

load_config
init_deploy_mode

GRAFANA_CONTAINER="crdb-grafana"
GRAFANA_PORT=3001
GRAFANA_IMAGE="grafana/grafana-oss:11.6.0"
GRAFANA_DS_DOCKER="${PROJECT_DIR}/grafana/provisioning/datasources/crdb.yml"
GRAFANA_DS_ROACHPROD="${PROJECT_DIR}/grafana/provisioning/datasources/crdb-roachprod.yml"

start_grafana() {
    if ! command -v docker &>/dev/null; then
        log_error "docker not found. Install Docker Desktop to run Grafana."
        exit 1
    fi

    if docker inspect "$GRAFANA_CONTAINER" &>/dev/null 2>&1; then
        log_warn "Grafana container '$GRAFANA_CONTAINER' already running."
        log_info "Dashboard: http://localhost:${GRAFANA_PORT}/d/ash-overview"
        log_info "Run: $0 stop  to remove it first."
        return
    fi

    if [[ "$DEPLOY_MODE" == "roachprod" ]]; then
        local ext_ip
        ext_ip=$(roachprod ip "${CLUSTER}:1" --external 2>/dev/null)
        patch_dashboard_links "http://${ext_ip}:26258"
        log_info "Generating roachprod-mode data source config..."
        # Move Docker-mode datasource out of the way to avoid duplicate default
        if [[ -f "$GRAFANA_DS_DOCKER" ]]; then
            mv "$GRAFANA_DS_DOCKER" "${GRAFANA_DS_DOCKER}.bak"
        fi
        cat > "$GRAFANA_DS_ROACHPROD" <<'EOF'
apiVersion: 1

datasources:
  - name: CockroachDB
    uid: cockroachdb
    type: postgres
    access: proxy
    url: host.docker.internal:26000
    database: defaultdb
    user: root
    isDefault: true
    editable: false
    jsonData:
      sslmode: disable
      maxOpenConns: 5
      maxIdleConns: 2
      connMaxLifetime: 600
      postgresVersion: 1400
      timescaledb: false
EOF
    else
        patch_dashboard_links "http://localhost:26258"
    fi

    log_info "Starting Grafana container (port $GRAFANA_PORT)..."
    docker run -d \
        --name "$GRAFANA_CONTAINER" \
        -p "${GRAFANA_PORT}:3000" \
        -e GF_SECURITY_ADMIN_USER=admin \
        -e GF_SECURITY_ADMIN_PASSWORD=admin \
        -e GF_AUTH_ANONYMOUS_ENABLED=true \
        -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
        -e "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/ash-overview.json" \
        -v "${PROJECT_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro" \
        -v "${PROJECT_DIR}/grafana/dashboards:/var/lib/grafana/dashboards:ro" \
        "$GRAFANA_IMAGE"

    log_info "Grafana started at http://localhost:${GRAFANA_PORT}"
    log_info "ASH Dashboard: http://localhost:${GRAFANA_PORT}/d/ash-overview"
}

stop_grafana() {
    if docker inspect "$GRAFANA_CONTAINER" &>/dev/null 2>&1; then
        log_info "Stopping Grafana container..."
        docker rm -f "$GRAFANA_CONTAINER"
        log_info "Grafana stopped."
    else
        log_warn "No Grafana container found."
    fi

    rm -f "$GRAFANA_DS_ROACHPROD"
    # Restore Docker-mode datasource
    if [[ -f "${GRAFANA_DS_DOCKER}.bak" ]]; then
        mv "${GRAFANA_DS_DOCKER}.bak" "$GRAFANA_DS_DOCKER"
    fi
}

ACTION="${1:-start}"

case "$ACTION" in
    start) start_grafana ;;
    stop)  stop_grafana ;;
    *)
        echo "Usage: $0 [start|stop]"
        exit 1
        ;;
esac
