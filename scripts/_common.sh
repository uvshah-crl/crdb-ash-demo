#!/usr/bin/env bash
# Shared helpers sourced by all ASH demo scripts.
# Usage: source "$(dirname "$0")/_common.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================
# Logging
# ============================================================

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

# ============================================================
# Configuration
# ============================================================

load_config() {
    local config_file="${PROJECT_DIR}/config.env"
    if [[ ! -f "$config_file" ]]; then
        log_error "config.env not found at $config_file"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$config_file"

    DEPLOY_MODE="${DEPLOY_MODE:-roachprod}"
    CLOUD="${CLOUD:-aws}"
    CRDB_VERSION="${CRDB_VERSION:-v26.2.0}"
    NUM_NODES="${NUM_NODES:-3}"
    AWS_MACHINE_TYPE="${AWS_MACHINE_TYPE:-m5d.2xlarge}"
    CLUSTER_LIFETIME="${CLUSTER_LIFETIME:-8h}"

    WORKLOAD_CONCURRENCY="${WORKLOAD_CONCURRENCY:-8}"
    WORKLOAD_DURATION_SECONDS="${WORKLOAD_DURATION_SECONDS:-600}"
}

# ============================================================
# Container Runtime Detection (Docker / Podman)
# ============================================================

detect_container_runtime() {
    if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
        return
    fi

    if command -v podman &>/dev/null && podman compose version &>/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
        COMPOSE_CMD="podman compose"
    elif command -v podman-compose &>/dev/null; then
        CONTAINER_RUNTIME="podman"
        COMPOSE_CMD="podman-compose"
    elif command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        CONTAINER_RUNTIME="docker"
        COMPOSE_CMD="docker-compose"
    else
        log_error "Neither docker nor podman found. Install one to use DEPLOY_MODE=docker."
        exit 1
    fi
    export CONTAINER_RUNTIME COMPOSE_CMD
    log_info "Container runtime: $CONTAINER_RUNTIME ($COMPOSE_CMD)"
}

# ============================================================
# AWS Identity & Cluster Name (roachprod mode only)
# ============================================================

derive_aws_identity() {
    PROFILE=$(grep -B 3 sso_account_id ~/.aws/config | grep profile | awk '{print $2}' | sed -e 's|\]||g' | head -1)
    if [[ -z "$PROFILE" ]]; then
        log_error "Could not derive AWS SSO profile from ~/.aws/config"
        log_error "Run: aws configure sso"
        exit 1
    fi
    export PROFILE

    ROACHPROD_USER=$(aws sts get-caller-identity --profile "$PROFILE" \
        --query 'Arn' --output text \
        | cut -d'/' -f2 \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d '_')

    if [[ -z "$ROACHPROD_USER" ]]; then
        log_error "Could not derive ROACHPROD_USER from AWS ARN"
        log_error "Run: aws sso login --profile \$PROFILE"
        exit 1
    fi
    export ROACHPROD_USER

    CLUSTER="${ROACHPROD_USER}-ash-demo"
    export CLUSTER
    save_cluster_name "$CLUSTER"

    log_info "AWS Profile: $PROFILE"
    log_info "Roachprod user: $ROACHPROD_USER"
    log_info "Cluster name: $CLUSTER"
}

# ============================================================
# Prerequisites
# ============================================================

ensure_prerequisites() {
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        detect_container_runtime
        return
    fi

    if [[ ! -f ~/.ssh/known_hosts ]]; then
        log_warn "Creating ~/.ssh/known_hosts (roachprod requires it)"
        touch ~/.ssh/known_hosts
        chmod 600 ~/.ssh/known_hosts
    fi

    if ! command -v roachprod &>/dev/null; then
        log_error "roachprod not found on PATH"
        exit 1
    fi

    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI not found. Install: brew install awscli"
        exit 1
    fi
}

ensure_dbworkload() {
    if ! command -v dbworkload &>/dev/null; then
        log_error "dbworkload not found on PATH"
        log_error "Install: pip install 'dbworkload[postgres]'"
        exit 1
    fi
}

fetch_rev_json() {
    local rev_json="${PROJECT_DIR}/rev.json"
    if [[ ! -f "$rev_json" ]]; then
        log_info "Downloading rev.json (AWS subnet config for crl-dev-revenue)..."
        curl -sL -o "$rev_json" \
            "https://raw.githubusercontent.com/cockroachdb/cockroach/2b79fbd6b0b0479281659cfa3fb3576db75e11ee/pkg/roachprod/vm/aws/rev.json"
    fi
    export REV_JSON="$rev_json"
}

# ============================================================
# Cluster name persistence
# ============================================================

CLUSTER_NAME_FILE="${PROJECT_DIR}/.cluster_name"

save_cluster_name() {
    echo "$1" > "$CLUSTER_NAME_FILE"
    export ASH_DEMO_CLUSTER="$1"
    log_info "Cluster name saved to .cluster_name: $1"
}

load_cluster_name() {
    if [[ -n "${ASH_DEMO_CLUSTER:-}" ]]; then
        CLUSTER="$ASH_DEMO_CLUSTER"
        export CLUSTER
        return 0
    fi
    if [[ -f "$CLUSTER_NAME_FILE" ]]; then
        CLUSTER=$(cat "$CLUSTER_NAME_FILE")
        export CLUSTER ASH_DEMO_CLUSTER="$CLUSTER"
        return 0
    fi
    return 1
}

# ============================================================
# Deploy-mode init (call this instead of derive_aws_identity
# in scripts that need cluster access)
# ============================================================

init_deploy_mode() {
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        detect_container_runtime
    elif load_cluster_name; then
        log_info "Using saved cluster: $CLUSTER"
    else
        derive_aws_identity
    fi
}

# ============================================================
# Abstraction: run_on_node / put_file / run_sql
# ============================================================

run_on_node() {
    local node="$1"; shift
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        "$CONTAINER_RUNTIME" exec "crdb-${node}" /cockroach/cockroach "$@"
    else
        # roachprod run passes the command as a single string via SSH.
        # Use printf %q to preserve quoting for multi-word arguments.
        local cmd="./cockroach"
        local arg
        for arg in "$@"; do
            cmd+=" $(printf '%q' "$arg")"
        done
        roachprod run "${CLUSTER}:${node}" -- "$cmd"
    fi
}

put_file() {
    local local_path="$1"
    local remote_path="$2"
    local node="${3:-1}"
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        "$CONTAINER_RUNTIME" cp "$local_path" "crdb-${node}:${remote_path}"
    else
        roachprod put "${CLUSTER}:${node}" "$local_path" "$remote_path"
    fi
}

run_sql() {
    local db="${1:-defaultdb}"
    local sql="$2"
    run_on_node 1 sql --insecure -d "$db" -e "$sql"
}

# ============================================================
# Cluster Lifecycle
# ============================================================

wait_for_cluster_ready() {
    local max_attempts=30
    local attempt=0
    log_info "Waiting for cluster to be ready..."
    while ! run_on_node 1 sql --insecure -e 'SELECT 1' &>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "Cluster not ready after $max_attempts attempts"
            exit 1
        fi
        sleep 5
    done
    log_info "Cluster is ready"
}

docker_compose_up() {
    log_info "Starting CockroachDB cluster via $COMPOSE_CMD..."
    $COMPOSE_CMD -f "${PROJECT_DIR}/compose.yml" up -d
}

docker_compose_down() {
    log_info "Stopping CockroachDB cluster via $COMPOSE_CMD..."
    $COMPOSE_CMD -f "${PROJECT_DIR}/compose.yml" down -v
}

# ============================================================
# HAProxy (local load balancer for workload connections)
# ============================================================

HAPROXY_PORT=26000
HAPROXY_CFG="${PROJECT_DIR}/haproxy.cfg"

start_haproxy() {
    if ! command -v haproxy &>/dev/null; then
        log_error "haproxy not found. Install: brew install haproxy"
        exit 1
    fi

    local existing_pid
    existing_pid=$(get_pid "haproxy")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        log_warn "HAProxy already running (PID $existing_pid)"
        return
    fi

    if [[ "$DEPLOY_MODE" == "roachprod" ]]; then
        generate_haproxy_cfg
    fi

    if [[ ! -f "$HAPROXY_CFG" ]]; then
        log_error "haproxy.cfg not found at $HAPROXY_CFG"
        exit 1
    fi

    log_info "Starting HAProxy on port $HAPROXY_PORT..."
    haproxy -f "$HAPROXY_CFG" -D -p "${PID_DIR}/haproxy.raw.pid"
    local pid
    pid=$(cat "${PID_DIR}/haproxy.raw.pid")
    rm -f "${PID_DIR}/haproxy.raw.pid"
    save_pid "haproxy" "$pid"
    log_info "HAProxy started (PID $pid) — SQL via localhost:$HAPROXY_PORT"
}

stop_haproxy() {
    local pid
    pid=$(get_pid "haproxy")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping HAProxy (PID $pid)..."
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        remove_pid "haproxy"
        log_info "HAProxy stopped"
    else
        remove_pid "haproxy"
    fi
}

check_haproxy_health() {
    local retries="${1:-1}"
    local interval="${2:-2}"
    local attempt=0
    while [[ $attempt -lt $retries ]]; do
        if (echo > /dev/tcp/localhost/${HAPROXY_PORT}) 2>/dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        if [[ $attempt -lt $retries ]]; then
            sleep "$interval"
        fi
    done
    return 1
}

ensure_haproxy() {
    if check_haproxy_health; then
        return
    fi
    log_warn "HAProxy not responding on port $HAPROXY_PORT — attempting restart..."
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        $COMPOSE_CMD -f "${PROJECT_DIR}/compose.yml" restart crdb-haproxy
    else
        stop_haproxy
        start_haproxy
    fi
    if check_haproxy_health 5 2; then
        log_info "HAProxy recovered"
    else
        log_error "HAProxy failed to recover after restart"
        exit 1
    fi
}

generate_docker_haproxy_cfg() {
    log_info "Generating haproxy.cfg for Docker cluster..."
    local cfg="$HAPROXY_CFG"
    cat > "$cfg" <<'DOCKERCFG'
global
    maxconn 4096
    log stdout format raw local0

defaults
    mode tcp
    timeout connect 10s
    timeout client  30m
    timeout server  30m
    option clitcpka
    option srvtcpka

listen crdb-sql
    bind *:26000
    mode tcp
    balance roundrobin
    option httpchk GET /health?ready=1
    server crdb-1 crdb-1:26257 check port 8080
    server crdb-2 crdb-2:26257 check port 8080
    server crdb-3 crdb-3:26257 check port 8080

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 5s
DOCKERCFG
    log_info "haproxy.cfg generated for Docker (3 backends)"
}

generate_haproxy_cfg() {
    log_info "Generating haproxy.cfg for roachprod cluster..."
    local cfg="$HAPROXY_CFG"
    local ips
    ips=$(roachprod ip "$CLUSTER" --external 2>/dev/null)

    cat > "$cfg" <<'HEADER'
global
    maxconn 4096
    log stdout format raw local0

defaults
    mode tcp
    timeout connect 10s
    timeout client  30m
    timeout server  30m
    option clitcpka
    option srvtcpka

listen crdb-sql
    bind *:26000
    mode tcp
    balance roundrobin
    option httpchk GET /health?ready=1
HEADER

    local i=1
    while IFS= read -r ip; do
        echo "    server crdb-${i} ${ip}:26257 check port 26258" >> "$cfg"
        i=$((i + 1))
    done <<< "$ips"

    cat >> "$cfg" <<'FOOTER'

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 5s
FOOTER

    log_info "haproxy.cfg generated with $((i - 1)) backends"
}

# ============================================================
# Grafana Dashboard Helpers
# ============================================================

patch_dashboard_links() {
    local db_console_url="$1"
    local dashboard="${PROJECT_DIR}/grafana/dashboards/ash-overview.json"
    if [[ ! -f "$dashboard" ]]; then
        log_warn "Dashboard not found at $dashboard — skipping link patch"
        return
    fi
    sed -i '' "s|http://[^\"]*:26258|${db_console_url}|g" "$dashboard"
    log_info "Dashboard DB Console link set to $db_console_url"
}

# ============================================================
# Workload Helpers
# ============================================================

get_workload_database() {
    local workload="${1:-}"
    case "$workload" in
        point-lookup) echo "hotspot" ;;
        *)            echo "defaultdb" ;;
    esac
}

get_workload_file() {
    local workload="${1:-}"
    case "$workload" in
        flight-schedules) echo "transactions.py" ;;
        train-events)     echo "transactionsJsonb.py" ;;
        point-lookup)     echo "transactionsHotspot.py" ;;
        *)
            log_error "Unknown workload: $workload"
            exit 1
            ;;
    esac
}

get_workload_args() {
    local workload="${1:-}"
    local args_file="${PROJECT_DIR}/workloads/${workload}/args.json"
    if [[ -f "$args_file" ]]; then
        cat "$args_file"
    else
        log_error "No args found: $args_file"
        exit 1
    fi
}

get_pgurl() {
    local db="${1:-defaultdb}"
    local app_name="${2:-}"
    local url="postgres://root@localhost:${HAPROXY_PORT}/${db}?sslmode=disable"

    if [[ -n "$app_name" ]]; then
        url="${url}&application_name=${app_name}"
    fi
    echo "$url"
}

# ============================================================
# PID file helpers
# ============================================================

PID_DIR="${PROJECT_DIR}/.pids"

save_pid() {
    local name="$1"
    local pid="$2"
    mkdir -p "$PID_DIR"
    echo "$pid" > "${PID_DIR}/${name}.pid"
}

get_pid() {
    local name="$1"
    local pid_file="${PID_DIR}/${name}.pid"
    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    fi
}

remove_pid() {
    local name="$1"
    rm -f "${PID_DIR}/${name}.pid"
}
