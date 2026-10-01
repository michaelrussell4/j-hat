#!/usr/bin/env bash
# ==============================================================================
# Enterprise Multi-Cluster Simulation Sanity Check & Verification Script
# Validates:
#   1. Zero-Trust Network Isolation (Negative Tests: C1/C2/C3 cannot talk directly)
#   2. Telemetry Gateway Reachability & Cross-Boundary Scraping
#   3. Cluster 3 Primary Prometheus Metric Federation
#   4. Cluster 3 DinD Nested Container Fleet Health
#   5. Local AI Stack (Ollama + Open WebUI) & Grafana Health
# ==============================================================================
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASSED_COUNT=0
FAILED_COUNT=0

report_pass() {
    local test_name="$1"
    local detail="${2:-}"
    echo -e "  [${GREEN}PASS${NC}] ${test_name}"
    if [ -n "$detail" ]; then
        echo -e "         ${CYAN}↳ ${detail}${NC}"
    fi
    PASSED_COUNT=$((PASSED_COUNT + 1))
}

report_fail() {
    local test_name="$1"
    local detail="${2:-}"
    echo -e "  [${RED}FAIL${NC}] ${test_name}"
    if [ -n "$detail" ]; then
        echo -e "         ${RED}↳ ${detail}${NC}"
    fi
    FAILED_COUNT=$((FAILED_COUNT + 1))
}

echo -e "\n${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD}  Multi-Cluster Enterprise Infrastructure Verification Suite        ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"

# ------------------------------------------------------------------------------
# 1. Zero-Trust Network Isolation Tests
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Phase 1] Network Isolation & Boundary Enforcement (Negative Tests)${NC}"

# Test 1.1: C1 cannot resolve C2 DNS
if docker exec c1-node-01 ping -c 1 -W 2 c2-node-01 >/dev/null 2>&1; then
    report_fail "DNS Isolation: c1-node-01 -> c2-node-01" "Cluster 1 was able to resolve and reach c2-node-01 hostname!"
else
    report_pass "DNS Isolation: c1-node-01 cannot resolve c2-node-01" "Hostname unresolvable as expected across isolated bridges"
fi

# Test 1.2: C1 cannot ping C2 IP directly (172.28.2.11)
if docker exec c1-node-01 ping -c 1 -W 2 172.28.2.11 >/dev/null 2>&1; then
    report_fail "IP Isolation: c1-node-01 -> 172.28.2.11" "Direct ICMP ping succeeded across isolated bridges!"
else
    report_pass "IP Isolation: c1-node-01 cannot ping c2-node-01 IP (172.28.2.11)" "100% packet loss / no route"
fi

# Test 1.3: C1 cannot ping C3 Prometheus IP directly (172.28.3.90)
if docker exec c1-node-01 ping -c 1 -W 2 172.28.3.90 >/dev/null 2>&1; then
    report_fail "IP Isolation: c1-node-01 -> 172.28.3.90" "Cluster 1 was able to ping Cluster 3 directly!"
else
    report_pass "IP Isolation: c1-node-01 cannot ping Cluster 3 Prometheus (172.28.3.90)" "Direct management network isolation verified"
fi

# Test 1.4: C2 cannot ping C1 IP directly (172.28.1.11)
if docker exec c2-node-01 ping -c 1 -W 2 172.28.1.11 >/dev/null 2>&1; then
    report_fail "IP Isolation: c2-node-01 -> 172.28.1.11" "Cluster 2 was able to ping Cluster 1 directly!"
else
    report_pass "IP Isolation: c2-node-01 cannot ping c1-node-01 IP (172.28.1.11)" "Reverse isolation confirmed"
fi

# Test 1.5: C3 Prometheus cannot scrape C1 node-exporter directly
if docker exec cluster-3-prometheus wget -T 2 -O- http://172.28.1.11:9100/metrics >/dev/null 2>&1; then
    report_fail "Direct Scrape Prevention: C3 Prometheus -> C1 Node" "Cluster 3 was able to bypass the Telemetry Gateway!"
else
    report_pass "Direct Scrape Prevention: C3 Prometheus cannot reach C1 directly" "Forces all cross-boundary telemetry through Gateway"
fi

# ------------------------------------------------------------------------------
# 2. Gateway Multi-Homed Reachability Tests
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Phase 2] Telemetry Gateway Cross-Boundary Connectivity${NC}"

# Test 2.1: C1 can reach Gateway on cluster-1-net
if docker exec c1-node-01 ping -c 1 -W 2 telemetry-gateway >/dev/null 2>&1; then
    report_pass "Gateway Reachability: c1-node-01 -> telemetry-gateway" "Cluster 1 communicates with Gateway on 172.28.1.0/24"
else
    report_fail "Gateway Reachability: c1-node-01 -> telemetry-gateway" "Gateway unreachable on cluster-1-net"
fi

# Test 2.2: C2 can reach Gateway on cluster-2-net
if docker exec c2-node-01 ping -c 1 -W 2 telemetry-gateway >/dev/null 2>&1; then
    report_pass "Gateway Reachability: c2-node-01 -> telemetry-gateway" "Cluster 2 communicates with Gateway on 172.28.2.0/24"
else
    report_fail "Gateway Reachability: c2-node-01 -> telemetry-gateway" "Gateway unreachable on cluster-2-net"
fi

# Test 2.3: C3 can reach Gateway on cluster-3-net
if docker exec cluster-3-prometheus wget -qO- http://telemetry-gateway:9090/-/healthy >/dev/null 2>&1; then
    report_pass "Gateway Reachability: C3 Prometheus -> telemetry-gateway:9090" "Gateway healthy on cluster-3-net"
else
    report_fail "Gateway Reachability: C3 Prometheus -> telemetry-gateway:9090" "Gateway health endpoint failed"
fi

# Test 2.4: Gateway actively scrapes all 6 nodes across C1 and C2
GATEWAY_UP_COUNT=$(docker exec telemetry-gateway wget -qO- "http://localhost:9090/api/v1/query?query=count(up{job=~\"cluster-.*\"}==1)" 2>/dev/null | grep -o '"value":\[[^]]*,"[0-9]*"' | awk -F'"' '{print $4}' || echo "0")
if [ "$GATEWAY_UP_COUNT" -ge 6 ]; then
    report_pass "Gateway Node Scraping: All 6 remote nodes UP" "Scraped 3 nodes from Cluster 1 + 3 nodes from Cluster 2"
else
    report_fail "Gateway Node Scraping" "Expected at least 6 UP targets on gateway, found: ${GATEWAY_UP_COUNT}"
fi

# ------------------------------------------------------------------------------
# 3. Cluster 3 Primary Prometheus & Federation Tests
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Phase 3] Primary Prometheus Telemetry Federation${NC}"

# Test 3.1: Gateway federation link is active
FEDERATION_STATUS=$(docker exec cluster-3-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"federate-gateway-clusters-1-and-2\"}" 2>/dev/null | grep -o '"value":\[[^]]*,"[0-9]*"' | awk -F'"' '{print $4}' || echo "0")
if [ "$FEDERATION_STATUS" = "1" ]; then
    report_pass "Federation Job Status: federate-gateway-clusters-1-and-2" "Federation endpoint reporting UP (1)"
else
    report_fail "Federation Job Status" "Federation scrape job is DOWN or not reporting 1"
fi

# Test 3.2: Cluster 1 federated metrics in Cluster 3 Prometheus
C1_FEDERATED_COUNT=$(docker exec cluster-3-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=count(up{cluster=\"cluster-1\"}==1)" 2>/dev/null | grep -o '"value":\[[^]]*,"[0-9]*"' | awk -F'"' '{print $4}' || echo "0")
if [ "$C1_FEDERATED_COUNT" -ge 3 ]; then
    report_pass "Federated Metrics: Cluster 1" "${C1_FEDERATED_COUNT} nodes successfully federated into Cluster 3 Prometheus"
else
    report_fail "Federated Metrics: Cluster 1" "Expected at least 3 nodes with cluster='cluster-1', found: ${C1_FEDERATED_COUNT}"
fi

# Test 3.3: Cluster 2 federated metrics in Cluster 3 Prometheus
C2_FEDERATED_COUNT=$(docker exec cluster-3-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=count(up{cluster=\"cluster-2\"}==1)" 2>/dev/null | grep -o '"value":\[[^]]*,"[0-9]*"' | awk -F'"' '{print $4}' || echo "0")
if [ "$C2_FEDERATED_COUNT" -ge 3 ]; then
    report_pass "Federated Metrics: Cluster 2" "${C2_FEDERATED_COUNT} nodes successfully federated into Cluster 3 Prometheus"
else
    report_fail "Federated Metrics: Cluster 2" "Expected at least 3 nodes with cluster='cluster-2', found: ${C2_FEDERATED_COUNT}"
fi

# ------------------------------------------------------------------------------
# 4. Nested Orchestrator (Docker-in-Docker) Tests
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Phase 4] Cluster 3 Nested Orchestrator (DinD)${NC}"

# Test 4.1: DinD internal daemon running
if docker exec cluster-3-dind docker info >/dev/null 2>&1; then
    report_pass "DinD Internal Docker Engine" "Internal dockerd daemon running and responsive"
else
    report_fail "DinD Internal Docker Engine" "Internal dockerd is not responsive"
fi

# Test 4.2: Nested containers running
DIND_CONTAINERS=$(docker exec cluster-3-dind docker ps --format '{{.Names}}' 2>/dev/null || echo "")
if echo "$DIND_CONTAINERS" | grep -q "nested-micro-api" && \
   echo "$DIND_CONTAINERS" | grep -q "nested-redis" && \
   echo "$DIND_CONTAINERS" | grep -q "nested-postgres"; then
    report_pass "Nested Container Fleet (micro-api, redis, postgres)" "All 3 nested containers are active"
else
    report_fail "Nested Container Fleet" "Missing one or more expected nested containers: ${DIND_CONTAINERS}"
fi

# Test 4.3: Micro API endpoint returns healthy status & database dependencies
MICRO_API_STATUS=$(docker exec cluster-3-prometheus wget -qO- "http://cluster-3-dind:8000/health" 2>/dev/null || echo "")
if echo "$MICRO_API_STATUS" | grep -q '"status": "healthy"'; then
    report_pass "Nested Micro API Connectivity & Storage" "Service healthy, connected to Redis and PostgreSQL"
else
    report_fail "Nested Micro API Connectivity" "Failed to retrieve healthy status from http://cluster-3-dind:8000/health"
fi

# ------------------------------------------------------------------------------
# 5. Local AI Stack & Grafana UI Tests
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Phase 5] Local AI Inference Stack & Grafana Dashboards${NC}"

# Test 5.1: Ollama API running
if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    LOADED_MODELS=$(curl -sf http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' || echo "")
    report_pass "Ollama AI Inference Server" "API responsive on port 11434 (${LOADED_MODELS})"
else
    report_fail "Ollama AI Inference Server" "Could not connect to http://localhost:11434/api/tags"
fi

# Test 5.2: Open WebUI frontend running
if curl -sf http://localhost:8080/ >/dev/null 2>&1; then
    report_pass "Open WebUI Frontend" "UI accessible on http://localhost:8080"
else
    report_fail "Open WebUI Frontend" "Could not connect to http://localhost:8080"
fi

# Test 5.3: Grafana UI and health
if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
    report_pass "Grafana Telemetry Dashboard" "Healthy and serving on http://localhost:3000"
else
    report_fail "Grafana Telemetry Dashboard" "Could not reach http://localhost:3000/api/health"
fi

# ------------------------------------------------------------------------------
# Verification Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}====================================================================${NC}"
echo -e "  Verification Results: ${GREEN}${PASSED_COUNT} Passed${NC}, ${RED}${FAILED_COUNT} Failed${NC}"
echo -e "${BOLD}====================================================================${NC}"

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ ALL ENTERPRISE REQUIREMENTS VALIDATED SUCCESSFULLY!${NC}\n"
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME CHECKS FAILED. Please review the output above.${NC}\n"
    exit 1
fi
