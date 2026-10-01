#!/usr/bin/env bash
# ==============================================================================
# Enterprise Multi-Cluster Simulation Teardown Script (Linux / macOS / WSL)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

REMOVE_VOLUMES=false
if [[ "${1:-}" == "-v" || "${1:-}" == "--volumes" ]]; then
    REMOVE_VOLUMES=true
fi

echo "Stopping multi-cluster simulation containers..."
if [ "$REMOVE_VOLUMES" = true ]; then
    echo "Warning: Removing all persistent volumes (including Ollama models and Prometheus TSDB)..."
    docker compose down -v --remove-orphans
else
    docker compose down --remove-orphans
fi

echo "Simulation stopped cleanly."
