#!/bin/bash
set -euo pipefail

# Remove the Containerlab topology and the local lab image.
# This is a convenience cleanup script for the VBox validation environment.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_NAME="xdp-vlan-policy-filter"
IMAGE="xdp-vlan-policy-filter:latest"
TOPOLOGY="${PROJECT_ROOT}/containerlab/xdp-vlan-policy-filter.clab.yml"

echo "=== Destroy ${LAB_NAME} ==="

echo ""
echo "== Step 1: Destroy containerlab topology =="
sudo containerlab destroy -t "${TOPOLOGY}" --cleanup || true

echo ""
echo "== Step 2: Remove Docker image =="
if docker images "${IMAGE}" --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE}$"; then
    docker rmi "${IMAGE}"
    echo "[OK] Docker image removed: ${IMAGE}"
else
    echo "[OK] Docker image already absent: ${IMAGE}"
fi

echo ""
echo "=== Cleanup complete ==="
