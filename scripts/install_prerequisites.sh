#!/usr/bin/env bash
# Checks and installs prerequisites for the ASH demo.
# macOS only — uses Homebrew for all installs.
#
# Usage: ./scripts/install_prerequisites.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
log_miss() { echo -e "${RED}[✗]${NC} $*"; }
log_skip() { echo -e "${YELLOW}[—]${NC} $*"; }
log_info() { echo -e "    $*"; }

ask_install() {
    local tool="$1"
    local response
    read -rp "    Install ${tool}? [y/N] " response </dev/tty
    [[ "$response" =~ ^[Yy]$ ]]
}

installed=()
skipped=()
failed=()

# ---- macOS check ----
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script supports macOS only."
    exit 1
fi

echo ""
echo "=== ASH Demo — Prerequisites Check ==="
echo ""

# ---- Homebrew ----
if command -v brew &>/dev/null; then
    log_ok "Homebrew"
else
    log_miss "Homebrew is required but not installed."
    log_info "Install it from: https://brew.sh"
    log_info "Run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# ---- Container runtime: Docker or Podman ----
echo ""
echo "--- Container Runtime ---"
has_docker=false
has_podman=false
command -v docker &>/dev/null && has_docker=true
command -v podman &>/dev/null && has_podman=true

if $has_docker && $has_podman; then
    log_ok "Docker"
    log_ok "Podman"
elif $has_docker; then
    log_ok "Docker"
    log_skip "Podman (not installed, Docker is available)"
elif $has_podman; then
    log_ok "Podman"
    log_skip "Docker (not installed, Podman is available)"
else
    log_miss "No container runtime found (Docker or Podman)"
    echo ""
    echo "    Which would you like to install?"
    echo "      1) Docker Desktop"
    echo "      2) Podman"
    echo "      3) Skip"
    read -rp "    Choice [1/2/3]: " choice </dev/tty
    case "$choice" in
        1)
            log_info "Installing Docker Desktop..."
            if brew install --cask docker; then
                log_ok "Docker Desktop installed — launch it from Applications to finish setup"
                installed+=("docker")
            else
                log_miss "Docker Desktop install failed"
                failed+=("docker")
            fi
            ;;
        2)
            log_info "Installing Podman..."
            if brew install podman; then
                log_ok "Podman installed"
                installed+=("podman")
            else
                log_miss "Podman install failed"
                failed+=("podman")
            fi
            ;;
        *)
            log_skip "Container runtime skipped"
            skipped+=("container-runtime")
            ;;
    esac
fi

# ---- AWS CLI ----
echo ""
echo "--- CLI Tools ---"
if command -v aws &>/dev/null; then
    log_ok "AWS CLI ($(aws --version 2>&1 | awk '{print $1}'))"
else
    log_miss "AWS CLI"
    if ask_install "AWS CLI"; then
        if brew install awscli; then
            log_ok "AWS CLI installed"
            installed+=("awscli")
        else
            log_miss "AWS CLI install failed"
            failed+=("awscli")
        fi
    else
        log_skip "AWS CLI skipped"
        skipped+=("awscli")
    fi
fi

# ---- HAProxy ----
if command -v haproxy &>/dev/null; then
    log_ok "HAProxy ($(haproxy -v 2>&1 | head -1 | awk '{print $3}'))"
else
    log_miss "HAProxy"
    if ask_install "HAProxy"; then
        if brew install haproxy; then
            log_ok "HAProxy installed"
            installed+=("haproxy")
        else
            log_miss "HAProxy install failed"
            failed+=("haproxy")
        fi
    else
        log_skip "HAProxy skipped"
        skipped+=("haproxy")
    fi
fi

# ---- Python 3 ----
echo ""
echo "--- Python & dbworkload ---"
if command -v python3 &>/dev/null; then
    log_ok "Python 3 ($(python3 --version 2>&1 | awk '{print $2}'))"
else
    log_miss "Python 3"
    if ask_install "Python 3"; then
        if brew install python; then
            log_ok "Python 3 installed"
            installed+=("python3")
        else
            log_miss "Python 3 install failed"
            failed+=("python3")
        fi
    else
        log_skip "Python 3 skipped"
        skipped+=("python3")
    fi
fi

# ---- dbworkload ----
if command -v dbworkload &>/dev/null; then
    log_ok "dbworkload"
else
    log_miss "dbworkload"
    if command -v python3 &>/dev/null; then
        if ask_install "dbworkload (via pip)"; then
            if pip3 install 'dbworkload[postgres]'; then
                log_ok "dbworkload installed"
                installed+=("dbworkload")
            else
                log_miss "dbworkload install failed"
                failed+=("dbworkload")
            fi
        else
            log_skip "dbworkload skipped"
            skipped+=("dbworkload")
        fi
    else
        log_skip "dbworkload skipped (Python 3 not available)"
        skipped+=("dbworkload")
    fi
fi

# ---- Summary ----
echo ""
echo "=== Summary ==="
if [[ ${#installed[@]} -gt 0 ]]; then
    echo -e "${GREEN}Installed:${NC} ${installed[*]}"
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Skipped:${NC}   ${skipped[*]}"
fi
if [[ ${#failed[@]} -gt 0 ]]; then
    echo -e "${RED}Failed:${NC}    ${failed[*]}"
fi
if [[ ${#installed[@]} -eq 0 && ${#skipped[@]} -eq 0 && ${#failed[@]} -eq 0 ]]; then
    echo -e "${GREEN}All prerequisites are already installed.${NC}"
fi
echo ""
