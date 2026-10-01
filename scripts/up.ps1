# ==============================================================================
# Enterprise Multi-Cluster Simulation Startup Script (Windows PowerShell)
# ==============================================================================
[CmdletBinding()]
param(
    [string]$Model = "llama3.2:1b"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  Multi-Cluster Enterprise Infrastructure Simulation Startup        " -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 1. Verify Docker prerequisites
Write-Host "`n[1/6] Checking Docker environment..." -ForegroundColor White
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "'docker' command not found in PATH. Please start Docker Desktop or install Docker."
    exit 1
}

try {
    docker compose version | Out-Null
} catch {
    Write-Error "'docker compose' plugin not found. Please ensure Docker Compose V2 is installed."
    exit 1
}

try {
    docker info | Out-Null
} catch {
    Write-Error "Docker daemon is not running. Please launch Docker Desktop and retry."
    exit 1
}
Write-Host "[OK] Docker engine and Compose are ready." -ForegroundColor Green

# 2. Setup Environment Variables
Write-Host "`n[2/6] Configuring environment settings..." -ForegroundColor White
if (-not (Test-Path ".env")) {
    Write-Host "Creating .env from .env.example..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
}

$envMap = @{}
Get-Content ".env" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $parts = $line.Split("=", 2)
        $envMap[$parts[0].Trim()] = $parts[1].Trim()
    }
}
$targetModel = if ($envMap.ContainsKey("OLLAMA_MODEL")) { $envMap["OLLAMA_MODEL"] } else { $Model }
$grafanaPort = if ($envMap.ContainsKey("GRAFANA_PORT")) { $envMap["GRAFANA_PORT"] } else { "3000" }
$webuiPort   = if ($envMap.ContainsKey("OPEN_WEBUI_PORT")) { $envMap["OPEN_WEBUI_PORT"] } else { "8080" }
$promPort    = if ($envMap.ContainsKey("PROMETHEUS_PORT")) { $envMap["PROMETHEUS_PORT"] } else { "9090" }

Write-Host "[OK] Target Ollama Model: $targetModel" -ForegroundColor Green

# 3. Build Images
Write-Host "`n[3/6] Building lightweight simulated node image..." -ForegroundColor White
docker compose build --pull c1-node-01

# 4. Start Infrastructure
Write-Host "`n[4/6] Orchestrating multi-cluster topology..." -ForegroundColor White
docker compose up -d --remove-orphans

# 5. Wait for Core Services
Write-Host "`n[5/6] Waiting for services to initialize..." -ForegroundColor White

Write-Host "  Waiting for Primary Prometheus..." -NoNewline
for ($i = 1; $i -le 30; $i++) {
    $res = docker exec cluster-3-prometheus wget -qO- http://localhost:9090/-/healthy 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host " Ready!" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 2
}

Write-Host "  Waiting for Grafana UI..." -NoNewline
for ($i = 1; $i -le 30; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$grafanaPort/api/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            Write-Host " Ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Retry
    }
    Start-Sleep -Seconds 2
}

Write-Host "  Waiting for DinD nested container fleet..." -NoNewline
for ($i = 1; $i -le 40; $i++) {
    $dindPs = docker exec cluster-3-dind docker ps -q 2>$null
    if ($LASTEXITCODE -eq 0 -and $dindPs) {
        $count = ($dindPs | Measure-Object).Count
        if ($count -ge 3) {
            Write-Host " Ready! ($count nested containers running)" -ForegroundColor Green
            break
        }
    }
    Start-Sleep -Seconds 2
}

Write-Host "  Waiting for Ollama AI daemon..." -NoNewline
for ($i = 1; $i -le 30; $i++) {
    $ollamaCheck = docker exec cluster-3-ollama ollama list 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host " Ready!" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 2
}

# 6. Pull Model in Ollama
Write-Host "`n[6/6] Checking AI Model in Ollama ($targetModel)..." -ForegroundColor White
$existingModels = docker exec cluster-3-ollama ollama list 2>$null
$modelPrefix = $targetModel.Split(":")[0]

if ($existingModels -match $modelPrefix) {
    Write-Host "[OK] Model '$targetModel' is already downloaded in Ollama." -ForegroundColor Green
} else {
    Write-Host "Pulling model '$targetModel' into Ollama container (this may take 1-3 minutes)..." -ForegroundColor Yellow
    docker exec -i cluster-3-ollama ollama pull "$targetModel"
    Write-Host "[OK] Successfully pulled '$targetModel'!" -ForegroundColor Green
}

Write-Host "`n====================================================================" -ForegroundColor Green
Write-Host "  Simulation Successfully Launched!                                 " -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "Access Interfaces:"
Write-Host "  • Grafana Dashboards:   http://localhost:$grafanaPort (Credentials: admin / admin)" -ForegroundColor Cyan
Write-Host "  • Open WebUI (AI Chat): http://localhost:$webuiPort" -ForegroundColor Cyan
Write-Host "  • Primary Prometheus:   http://localhost:$promPort" -ForegroundColor Cyan
Write-Host "`nNext step: Run the sanity check script:"
Write-Host "  PowerShell: .\scripts\verify.ps1" -ForegroundColor Yellow
Write-Host "  Bash:       ./scripts/verify.sh" -ForegroundColor Yellow
