# ==============================================================================
# Enterprise Multi-Cluster Simulation Sanity Check & Verification Script
# (Windows PowerShell Version)
# ==============================================================================
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

$passedCount = 0
$failedCount = 0

function Report-Pass {
    param([string]$TestName, [string]$Detail)
    Write-Host "  [PASS] $TestName" -ForegroundColor Green
    if ($Detail) {
        Write-Host "         ↳ $Detail" -ForegroundColor DarkCyan
    }
    $script:passedCount++
}

function Report-Fail {
    param([string]$TestName, [string]$Detail)
    Write-Host "  [FAIL] $TestName" -ForegroundColor Red
    if ($Detail) {
        Write-Host "         ↳ $Detail" -ForegroundColor DarkRed
    }
    $script:failedCount++
}

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "  Multi-Cluster Enterprise Infrastructure Verification Suite        " -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. Zero-Trust Network Isolation Tests
# ------------------------------------------------------------------------------
Write-Host "`n[Phase 1] Network Isolation & Boundary Enforcement (Negative Tests)" -ForegroundColor White

# Test 1.1: C1 cannot resolve C2 DNS
$null = docker exec c1-node-01 ping -c 1 -W 2 c2-node-01 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Fail "DNS Isolation: c1-node-01 -> c2-node-01" "Cluster 1 was able to resolve and reach c2-node-01 hostname!"
} else {
    Report-Pass "DNS Isolation: c1-node-01 cannot resolve c2-node-01" "Hostname unresolvable as expected across isolated bridges"
}

# Test 1.2: C1 cannot ping C2 IP directly (172.28.2.11)
$null = docker exec c1-node-01 ping -c 1 -W 2 172.28.2.11 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Fail "IP Isolation: c1-node-01 -> 172.28.2.11" "Direct ICMP ping succeeded across isolated bridges!"
} else {
    Report-Pass "IP Isolation: c1-node-01 cannot ping c2-node-01 IP (172.28.2.11)" "100% packet loss / no route"
}

# Test 1.3: C1 cannot ping C3 Prometheus IP directly (172.28.3.90)
$null = docker exec c1-node-01 ping -c 1 -W 2 172.28.3.90 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Fail "IP Isolation: c1-node-01 -> 172.28.3.90" "Cluster 1 was able to ping Cluster 3 directly!"
} else {
    Report-Pass "IP Isolation: c1-node-01 cannot ping Cluster 3 Prometheus (172.28.3.90)" "Direct management network isolation verified"
}

# Test 1.4: C2 cannot ping C1 IP directly (172.28.1.11)
$null = docker exec c2-node-01 ping -c 1 -W 2 172.28.1.11 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Fail "IP Isolation: c2-node-01 -> 172.28.1.11" "Cluster 2 was able to ping Cluster 1 directly!"
} else {
    Report-Pass "IP Isolation: c2-node-01 cannot ping c1-node-01 IP (172.28.1.11)" "Reverse isolation confirmed"
}

# Test 1.5: C3 Prometheus cannot scrape C1 node-exporter directly
$null = docker exec cluster-3-prometheus wget -T 2 -O- http://172.28.1.11:9100/metrics 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Fail "Direct Scrape Prevention: C3 Prometheus -> C1 Node" "Cluster 3 was able to bypass the Telemetry Gateway!"
} else {
    Report-Pass "Direct Scrape Prevention: C3 Prometheus cannot reach C1 directly" "Forces all cross-boundary telemetry through Gateway"
}

# ------------------------------------------------------------------------------
# 2. Gateway Multi-Homed Reachability Tests
# ------------------------------------------------------------------------------
Write-Host "`n[Phase 2] Telemetry Gateway Cross-Boundary Connectivity" -ForegroundColor White

# Test 2.1: C1 can reach Gateway on cluster-1-net
$null = docker exec c1-node-01 ping -c 1 -W 2 telemetry-gateway 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Pass "Gateway Reachability: c1-node-01 -> telemetry-gateway" "Cluster 1 communicates with Gateway on 172.28.1.0/24"
} else {
    Report-Fail "Gateway Reachability: c1-node-01 -> telemetry-gateway" "Gateway unreachable on cluster-1-net"
}

# Test 2.2: C2 can reach Gateway on cluster-2-net
$null = docker exec c2-node-01 ping -c 1 -W 2 telemetry-gateway 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Pass "Gateway Reachability: c2-node-01 -> telemetry-gateway" "Cluster 2 communicates with Gateway on 172.28.2.0/24"
} else {
    Report-Fail "Gateway Reachability: c2-node-01 -> telemetry-gateway" "Gateway unreachable on cluster-2-net"
}

# Test 2.3: C3 can reach Gateway on cluster-3-net
$null = docker exec cluster-3-prometheus wget -qO- http://telemetry-gateway:9090/-/healthy 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Pass "Gateway Reachability: C3 Prometheus -> telemetry-gateway:9090" "Gateway healthy on cluster-3-net"
} else {
    Report-Fail "Gateway Reachability: C3 Prometheus -> telemetry-gateway:9090" "Gateway health endpoint failed"
}

# Test 2.4: Gateway actively scrapes all 6 nodes across C1 and C2
$gwUp = docker exec telemetry-gateway wget -qO- "http://localhost:9090/api/v1/query?query=count(up{job=~\"cluster-.*\"}==1)" 2>$null
if ($gwUp -match '"value":\[[^]]*,"([0-9]+)"') {
    $count = [int]$matches[1]
    if ($count -ge 6) {
        Report-Pass "Gateway Node Scraping: All 6 remote nodes UP" "Scraped 3 nodes from Cluster 1 + 3 nodes from Cluster 2"
    } else {
        Report-Fail "Gateway Node Scraping" "Expected at least 6 UP targets on gateway, found: $count"
    }
} else {
    Report-Fail "Gateway Node Scraping" "Could not parse query response from gateway"
}

# ------------------------------------------------------------------------------
# 3. Cluster 3 Primary Prometheus & Federation Tests
# ------------------------------------------------------------------------------
Write-Host "`n[Phase 3] Primary Prometheus Telemetry Federation" -ForegroundColor White

# Test 3.1: Gateway federation link is active
$fedStatus = docker exec cluster-3-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"federate-gateway-clusters-1-and-2\"}" 2>$null
if ($fedStatus -match '"value":\[[^]]*,"1"') {
    Report-Pass "Federation Job Status: federate-gateway-clusters-1-and-2" "Federation endpoint reporting UP (1)"
} else {
    Report-Fail "Federation Job Status" "Federation scrape job is DOWN or not reporting 1"
}

# Test 3.2: Cluster 1 federated metrics in Cluster 3 Prometheus
$c1Fed = docker exec cluster-3-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=count(up{cluster=\"cluster-1\"}==1)" 2>$null
if ($c1Fed -match '"value":\[[^]]*,"([0-9]+)"' -and [int]$matches[1] -ge 3) {
    Report-Pass "Federated Metrics: Cluster 1" "$($matches[1]) nodes successfully federated into Cluster 3 Prometheus"
} else {
    Report-Fail "Federated Metrics: Cluster 1" "Expected at least 3 nodes with cluster='cluster-1'"
}

# Test 3.3: Cluster 2 federated metrics in Cluster 3 Prometheus
$c2Fed = docker exec cluster-3-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=count(up{cluster=\"cluster-2\"}==1)" 2>$null
if ($c2Fed -match '"value":\[[^]]*,"([0-9]+)"' -and [int]$matches[1] -ge 3) {
    Report-Pass "Federated Metrics: Cluster 2" "$($matches[1]) nodes successfully federated into Cluster 3 Prometheus"
} else {
    Report-Fail "Federated Metrics: Cluster 2" "Expected at least 3 nodes with cluster='cluster-2'"
}

# ------------------------------------------------------------------------------
# 4. Nested Orchestrator (Docker-in-Docker) Tests
# ------------------------------------------------------------------------------
Write-Host "`n[Phase 4] Cluster 3 Nested Orchestrator (DinD)" -ForegroundColor White

# Test 4.1: DinD internal daemon running
$dindInfo = docker exec cluster-3-dind docker info 2>&1
if ($LASTEXITCODE -eq 0) {
    Report-Pass "DinD Internal Docker Engine" "Internal dockerd daemon running and responsive"
} else {
    Report-Fail "DinD Internal Docker Engine" "Internal dockerd is not responsive"
}

# Test 4.2: Nested containers running
$dindContainers = docker exec cluster-3-dind docker ps --format "{{.Names}}" 2>$null
if ($dindContainers -match "nested-micro-api" -and $dindContainers -match "nested-redis" -and $dindContainers -match "nested-postgres") {
    Report-Pass "Nested Container Fleet (micro-api, redis, postgres)" "All 3 nested containers are active"
} else {
    Report-Fail "Nested Container Fleet" "Missing one or more expected nested containers: $dindContainers"
}

# Test 4.3: Micro API endpoint returns healthy status & database dependencies
$microApiHealth = docker exec cluster-3-prometheus wget -qO- "http://cluster-3-dind:8000/health" 2>$null
if ($microApiHealth -match '"status":\s*"healthy"') {
    Report-Pass "Nested Micro API Connectivity & Storage" "Service healthy, connected to Redis and PostgreSQL"
} else {
    Report-Fail "Nested Micro API Connectivity" "Failed to retrieve healthy status from http://cluster-3-dind:8000/health"
}

# ------------------------------------------------------------------------------
# 5. Local AI Stack & Grafana UI Tests
# ------------------------------------------------------------------------------
Write-Host "`n[Phase 5] Local AI Inference Stack & Grafana Dashboards" -ForegroundColor White

# Test 5.1: Ollama API running
try {
    $ollamaResp = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3 -ErrorAction Stop
    $modelList = ($ollamaResp.models | ForEach-Object { $_.name }) -join ", "
    Report-Pass "Ollama AI Inference Server" "API responsive on port 11434 ($modelList)"
} catch {
    Report-Fail "Ollama AI Inference Server" "Could not connect to http://localhost:11434/api/tags: $_"
}

# Test 5.2: Open WebUI frontend running
try {
    $webuiResp = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    if ($webuiResp.StatusCode -eq 200) {
        Report-Pass "Open WebUI Frontend" "UI accessible on http://localhost:8080"
    } else {
        Report-Fail "Open WebUI Frontend" "Returned status $($webuiResp.StatusCode)"
    }
} catch {
    Report-Fail "Open WebUI Frontend" "Could not connect to http://localhost:8080: $_"
}

# Test 5.3: Grafana UI and health
try {
    $grafanaResp = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -TimeoutSec 3 -ErrorAction Stop
    if ($grafanaResp.database -eq "ok") {
        Report-Pass "Grafana Telemetry Dashboard" "Healthy and serving on http://localhost:3000"
    } else {
        Report-Fail "Grafana Telemetry Dashboard" "Grafana health status: $($grafanaResp.database)"
    }
} catch {
    Report-Fail "Grafana Telemetry Dashboard" "Could not connect to http://localhost:3000/api/health: $_"
}

# ------------------------------------------------------------------------------
# Verification Summary
# ------------------------------------------------------------------------------
Write-Host "`====================================================================" -ForegroundColor White
Write-Host "  Verification Results: " -NoNewline
Write-Host "$passedCount Passed" -ForegroundColor Green -NoNewline
Write-Host ", " -NoNewline
Write-Host "$failedCount Failed" -ForegroundColor Red
Write-Host "====================================================================" -ForegroundColor White

if ($failedCount -eq 0) {
    Write-Host "ALL ENTERPRISE REQUIREMENTS VALIDATED SUCCESSFULLY!`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "SOME CHECKS FAILED. Please review the output above.`n" -ForegroundColor Red
    exit 1
}
