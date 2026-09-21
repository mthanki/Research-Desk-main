#!/usr/bin/env bash
# ==============================================================================
# dev-open.sh — Kubuntu / Linux equivalent for dev-open.ps1
#
# SYNOPSIS:
#     Open every Research Desk web UI that is currently running.
#
# DESCRIPTION:
#     Probes each published port and opens ONLY the services that answer, then
#     prints a summary of what was opened and what was not.
#
# USAGE:
#     ./scripts/dev-open.sh          # Open whatever is already running
#     ./scripts/dev-open.sh --up     # Start default stack first, then open
# ==============================================================================

set -euo pipefail

# ANSI Color formatting
COLOR_RESET="\033[0m"
COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_WHITE="\033[1;37m"
COLOR_GRAY="\033[0;90m"
COLOR_RED="\033[1;31m"

# Handle arguments
START_UP=false
for arg in "$@"; do
    case "$arg" in
        -u|--up|-Up|up)
            START_UP=true
            ;;
        -h|--help)
            echo "Usage: $0 [--up]"
            echo "  --up    Bring the default stack up first (docker compose up -d), wait, then open."
            exit 0
            ;;
    esac
done

# Set repo root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$START_UP" = true ]; then
    echo -e ""
    echo -e "${COLOR_CYAN}Starting the default stack...${COLOR_RESET}"
    cd "$REPO_ROOT"
    if ! docker compose up -d; then
        echo -e ""
        echo -e "${COLOR_RED}docker compose failed. Is Docker daemon running?${COLOR_RESET}"
        exit 1
    fi
    echo -e "${COLOR_GRAY}Waiting for ports to open...${COLOR_RESET}"
    sleep 3
fi

# Define services: Name | URL | Port | Start command
declare -a SERVICE_NAMES=(
    "Frontend"
    "API docs (Swagger)"
    "Qdrant dashboard"
    "Langfuse"
    "pgweb (database)"
)

declare -a SERVICE_URLS=(
    "http://localhost:3000"
    "http://localhost:8000/docs"
    "http://localhost:6333/dashboard"
    "http://localhost:3001"
    "http://localhost:8081"
)

declare -a SERVICE_PORTS=(
    3000
    8000
    6333
    3001
    8081
)

declare -a SERVICE_STARTS=(
    "docker compose up -d web"
    "docker compose up -d api"
    "docker compose up -d qdrant"
    "docker compose --profile obs up -d"
    "docker compose --profile tools up -d pgweb"
)

# Helper function to check if a TCP port is open on 127.0.0.1
test_port() {
    local port="$1"
    python3 -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.5)
try:
    s.connect(('127.0.0.1', $port))
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

# Check browser launcher (xdg-open is default on Kubuntu/KDE and Linux)
OPEN_CMD=""
if command -v xdg-open >/dev/null 2>&1; then
    OPEN_CMD="xdg-open"
elif command -v kde-open5 >/dev/null 2>&1; then
    OPEN_CMD="kde-open5"
elif command -v kde-open >/dev/null 2>&1; then
    OPEN_CMD="kde-open"
elif command -v sensible-browser >/dev/null 2>&1; then
    OPEN_CMD="sensible-browser"
fi

RUNNING_NAMES=()
RUNNING_URLS=()
STOPPED_NAMES=()
STOPPED_STARTS=()

num_services="${#SERVICE_NAMES[@]}"
for ((i=0; i<num_services; i++)); do
    port="${SERVICE_PORTS[$i]}"
    name="${SERVICE_NAMES[$i]}"
    url="${SERVICE_URLS[$i]}"
    start_cmd="${SERVICE_STARTS[$i]}"

    if test_port "$port"; then
        RUNNING_NAMES+=("$name")
        RUNNING_URLS+=("$url")
    else
        STOPPED_NAMES+=("$name")
        STOPPED_STARTS+=("$start_cmd")
    fi
done

echo -e ""
if [ "${#RUNNING_NAMES[@]}" -eq 0 ]; then
    echo -e "${COLOR_YELLOW}Nothing is running.${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_GRAY}Start the stack with:${COLOR_RESET}"
    echo -e "    ${COLOR_WHITE}./scripts/dev-open.sh --up${COLOR_RESET}"
    echo -e ""
    exit 0
fi

echo -e "${COLOR_GREEN}Opening ${#RUNNING_NAMES[@]} service(s)${COLOR_RESET}"
for ((i=0; i<${#RUNNING_NAMES[@]}; i++)); do
    printf "  %-20s %s\n" "${RUNNING_NAMES[$i]}" "${RUNNING_URLS[$i]}"
    if [ -n "$OPEN_CMD" ]; then
        "$OPEN_CMD" "${RUNNING_URLS[$i]}" >/dev/null 2>&1 &
        sleep 0.4
    fi
done

if [ "${#STOPPED_NAMES[@]}" -gt 0 ]; then
    echo -e ""
    echo -e "${COLOR_GRAY}Not running:${COLOR_RESET}"
    for ((i=0; i<${#STOPPED_NAMES[@]}; i++)); do
        printf "  \033[0;90m%-20s %s\033[0m\n" "${STOPPED_NAMES[$i]}" "${STOPPED_STARTS[$i]}"
    done
fi

echo -e ""
