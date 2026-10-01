# ==============================================================================
# Enterprise Multi-Cluster Simulation Teardown Script (Windows PowerShell)
# ==============================================================================
[CmdletBinding()]
param(
    [switch]$Volumes
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

Write-Host "Stopping multi-cluster simulation containers..." -ForegroundColor Cyan

if ($Volumes) {
    Write-Host "Warning: Removing all persistent volumes (including Ollama models and Prometheus TSDB)..." -ForegroundColor Yellow
    docker compose down -v --remove-orphans
} else {
    docker compose down --remove-orphans
}

Write-Host "Simulation stopped cleanly." -ForegroundColor Green
