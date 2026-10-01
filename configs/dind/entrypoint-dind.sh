#!/bin/sh
set -e

echo "[DinD] Starting internal Docker daemon in background..."
dockerd-entrypoint.sh &
DOCKERD_PID=$!

echo "[DinD] Waiting for internal Docker daemon socket to be ready..."
RETRIES=60
until docker info > /dev/null 2>&1 || [ $RETRIES -eq 0 ]; do
    echo "[DinD] Waiting for dockerd... ($RETRIES retries left)"
    RETRIES=$((RETRIES - 1))
    sleep 1
done

if [ $RETRIES -eq 0 ]; then
    echo "[DinD] ERROR: Internal dockerd failed to start within timeout."
    exit 1
fi

echo "[DinD] Docker daemon is ready! Deploying nested container fleet..."

if [ -f /dind-workloads/docker-compose.yml ]; then
    cd /dind-workloads
    docker compose up -d --build --remove-orphans || true
    echo "[DinD] Nested containers successfully provisioned:"
    docker ps
else
    echo "[DinD] Warning: /dind-workloads/docker-compose.yml not found."
fi

# Wait for dockerd PID so container continues running
wait $DOCKERD_PID
