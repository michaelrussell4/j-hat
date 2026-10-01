#!/usr/bin/env bash
# ==============================================================================
# Enterprise Multi-Cluster Simulation Startup Script (Linux / macOS / WSL)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD}  Multi-Cluster Enterprise Infrastructure Simulation Startup        ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"

# 1. Verify Docker prerequisites
echo -e "\n${BOLD}[1/6] Checking Docker environment...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR] 'docker' command not found in PATH.${NC}"
    echo -e "Please install Docker Engine or Docker Desktop and ensure it is in your PATH."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${RED}[ERROR] 'docker compose' plugin not found.${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}[ERROR] Docker daemon is not running or current user lacks socket permissions.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker engine and Compose are ready.${NC}"

# 2. Setup Environment Variables
echo -e "\n${BOLD}[2/6] Configuring environment settings...${NC}"
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env from .env.example...${NC}"
    cp .env.example .env
fi
# Source .env
set -a
# shellcheck disable=SC1091
source .env
set +a
MODEL_NAME="${OLLAMA_MODEL:-llama3.2:1b}"
echo -e "${GREEN}✓ Target Ollama Model: ${MODEL_NAME}${NC}"

# Ensure script permissions inside configs/images
chmod +x "${ROOT_DIR}/images/simulated-node/entrypoint.sh" 2>/dev/null || true
chmod +x "${ROOT_DIR}/configs/dind/entrypoint-dind.sh" 2>/dev/null || true

# 3. Build Images
echo -e "\n${BOLD}[3/6] Building lightweight simulated node image...${NC}"
docker compose build --pull c1-node-01

# 4. Start Infrastructure
echo -e "\n${BOLD}[4/6] Orchestrating multi-cluster topology...${NC}"
docker compose up -d --remove-orphans

# 5. Wait for Core Services
echo -e "\n${BOLD}[5/6] Waiting for services to initialize...${NC}"

echo -n "  Waiting for Primary Prometheus..."
for i in {1..30}; do
    if docker exec cluster-3-prometheus wget -qO- http://localhost:9090/-/healthy >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e " ${YELLOW}Warning: Timeout waiting for Prometheus.${NC}"
    fi
    sleep 2
done

echo -n "  Waiting for Grafana UI..."
for i in {1..30}; do
    if curl -sf http://localhost:${GRAFANA_PORT:-3000}/api/health >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e " ${YELLOW}Warning: Timeout waiting for Grafana.${NC}"
    fi
    sleep 2
done

echo -n "  Waiting for DinD nested container fleet..."
for i in {1..40}; do
    if docker exec cluster-3-dind docker ps >/dev/null 2>&1; then
        RUNNING_CONTAINERS=$(docker exec cluster-3-dind docker ps -q | wc -l | tr -d ' ')
        if [ "$RUNNING_CONTAINERS" -ge 3 ]; then
            echo -e " ${GREEN}Ready! (${RUNNING_CONTAINERS} nested containers running)${NC}"
            break
        fi
    fi
    if [ "$i" -eq 40 ]; then
        echo -e " ${YELLOW}Warning: Nested DinD stack still warming up.${NC}"
    fi
    sleep 2
done

echo -n "  Waiting for Ollama AI daemon..."
for i in {1..30}; do
    if docker exec cluster-3-ollama ollama list >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e " ${YELLOW}Warning: Timeout waiting for Ollama.${NC}"
    fi
    sleep 2
done

# 6. Pull Model in Ollama
echo -e "\n${BOLD}[6/6] Checking AI Model in Ollama (${MODEL_NAME})...${NC}"
if docker exec cluster-3-ollama ollama list | grep -q "${MODEL_NAME%%:*}"; then
    echo -e "${GREEN}✓ Model '${MODEL_NAME}' is already downloaded in Ollama.${NC}"
else
    echo -e "${YELLOW}Pulling model '${MODEL_NAME}' into Ollama container (this may take 1-3 minutes depending on network)...${NC}"
    docker exec -i cluster-3-ollama ollama pull "${MODEL_NAME}"
    echo -e "${GREEN}✓ Successfully pulled '${MODEL_NAME}'!${NC}"
fi

echo -e "\n${GREEN}${BOLD}====================================================================${NC}"
echo -e "${GREEN}${BOLD}  Simulation Successfully Launched!                                 ${NC}"
echo -e "${GREEN}${BOLD}====================================================================${NC}"
echo -e "Access Interfaces:"
echo -e "  • ${BOLD}Grafana Dashboards:${NC}      http://localhost:${GRAFANA_PORT:-3000} (Credentials: admin / admin)"
echo -e "  • ${BOLD}Open WebUI (AI Chat):${NC}    http://localhost:${OPEN_WEBUI_PORT:-8080}"
echo -e "  • ${BOLD}Primary Prometheus:${NC}      http://localhost:${PROMETHEUS_PORT:-9090}"
echo -e "  • ${BOLD}Ollama API:${NC}              http://localhost:${OLLAMA_PORT:-11434}"
echo -e "\nNext step: Run the sanity check script:"
echo -e "  ${CYAN}./scripts/verify.sh${NC}"
